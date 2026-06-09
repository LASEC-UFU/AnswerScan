package com.example.answer_scan.omr

import android.util.Log
import org.opencv.core.Core
import org.opencv.core.Mat
import org.opencv.core.MatOfInt
import org.opencv.core.MatOfPoint
import org.opencv.core.MatOfPoint2f
import org.opencv.core.Point
import org.opencv.core.Rect
import org.opencv.imgproc.Imgproc
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max

class MarkerDetector {

    companion object {
        private const val TAG = "MarkerDetector"
    }

    data class MarkerBox(
        val center: Point,
        val bounds: Rect,
        val area: Double,
        val density: Double,
        val solidity: Double,
    ) {
        val left: Double get() = bounds.x.toDouble()
        val right: Double get() = (bounds.x + bounds.width).toDouble()
        val top: Double get() = bounds.y.toDouble()
        val bottom: Double get() = (bounds.y + bounds.height).toDouble()
        val squareness: Double
            get() = if (bounds.width > bounds.height) {
                bounds.height.toDouble() / bounds.width
            } else {
                bounds.width.toDouble() / bounds.height
            }
    }

    data class DetectedMarkers(
        val tl: MarkerBox,
        val tr: MarkerBox,
        val bl: MarkerBox,
        val br: MarkerBox,
    ) {
        val templateCorners: List<Point> by lazy {
            listOf(
                Point(tl.right, tl.bottom),
                Point(tr.left, tr.bottom),
                Point(bl.right, bl.top),
                Point(br.left, br.top),
            )
        }
    }

    fun detect(binary: Mat, imgW: Int, imgH: Int): DetectedMarkers? {
        val contoursInput = binary.clone()
        val contours = ArrayList<MatOfPoint>()
        val hierarchy = Mat()
        Imgproc.findContours(
            contoursInput,
            contours,
            hierarchy,
            Imgproc.RETR_EXTERNAL,
            Imgproc.CHAIN_APPROX_SIMPLE,
        )
        contoursInput.release()
        hierarchy.release()

        val imgArea = imgW.toLong() * imgH
        val minArea = imgArea * TemplateConfig.MARKER_MIN_AREA_FRAC
        val maxArea = imgArea * TemplateConfig.MARKER_MAX_AREA_FRAC
        val candidates = mutableListOf<MarkerBox>()

        for (contour in contours) {
            val area = Imgproc.contourArea(contour)
            if (area < minArea || area > maxArea) {
                contour.release()
                continue
            }

            val bounds = Imgproc.boundingRect(contour)
            if (bounds.width <= 0 || bounds.height <= 0) {
                contour.release()
                continue
            }

            val aspect = bounds.width.toDouble() / bounds.height
            if (aspect < TemplateConfig.MARKER_MIN_ASPECT ||
                aspect > TemplateConfig.MARKER_MAX_ASPECT
            ) {
                contour.release()
                continue
            }

            val roi = binary.submat(bounds)
            val density = Core.countNonZero(roi).toDouble() /
                (bounds.width.toDouble() * bounds.height)
            roi.release()
            if (density < TemplateConfig.MARKER_MIN_DENSITY) {
                contour.release()
                continue
            }

            val solidity = computeSolidity(contour)
            if (solidity < TemplateConfig.MARKER_MIN_SOLIDITY) {
                contour.release()
                continue
            }

            val approx = MatOfPoint2f()
            val contour2f = MatOfPoint2f(*contour.toArray())
            Imgproc.approxPolyDP(
                contour2f,
                approx,
                Imgproc.arcLength(contour2f, true) * 0.04,
                true,
            )
            val approxPoints = approx.total().toInt()
            contour2f.release()
            approx.release()

            if (approxPoints !in 4..10) {
                contour.release()
                continue
            }

            candidates.add(
                MarkerBox(
                    center = Point(
                        bounds.x + bounds.width / 2.0,
                        bounds.y + bounds.height / 2.0,
                    ),
                    bounds = bounds,
                    area = area,
                    density = density,
                    solidity = solidity,
                ),
            )
            contour.release()
        }

        Log.d(TAG, "Marker candidates: ${candidates.size}")
        if (candidates.size < 4) return null

        // Strategy 1: constrained corner-region search (MARKER_CORNER_REGION_FRAC = 0.45)
        val byCorner = selectByCornerRegions(candidates, imgW, imgH)
        if (byCorner != null) {
            Log.d(TAG, "Markers found via corner-region search")
            return byCorner
        }

        // Strategy 2: centroid-based quadrant fallback — handles heavy perspective tilt,
        // off-center framing, and variable zoom where markers exceed the corner region.
        Log.d(TAG, "Corner search exhausted, trying quadrant fallback")
        return selectByQuadrants(candidates, imgW, imgH)
    }

    private fun selectByCornerRegions(
        candidates: List<MarkerBox>,
        imgW: Int,
        imgH: Int,
    ): DetectedMarkers? = validateAndBuild(
        selectCandidate(candidates, imgW, imgH, Corner.TOP_LEFT),
        selectCandidate(candidates, imgW, imgH, Corner.TOP_RIGHT),
        selectCandidate(candidates, imgW, imgH, Corner.BOTTOM_LEFT),
        selectCandidate(candidates, imgW, imgH, Corner.BOTTOM_RIGHT),
    )

    /**
     * Fallback when corner-region search fails.
     * Computes the centroid of all candidates and partitions them into 4 quadrants,
     * then picks the best marker per quadrant using corner-proximity scoring.
     */
    private fun selectByQuadrants(
        candidates: List<MarkerBox>,
        imgW: Int,
        imgH: Int,
    ): DetectedMarkers? {
        if (candidates.size < 4) return null

        val cx = candidates.map { it.center.x }.average()
        val cy = candidates.map { it.center.y }.average()

        val tlCands = candidates.filter { it.center.x < cx && it.center.y < cy }
        val trCands = candidates.filter { it.center.x >= cx && it.center.y < cy }
        val blCands = candidates.filter { it.center.x < cx && it.center.y >= cy }
        val brCands = candidates.filter { it.center.x >= cx && it.center.y >= cy }

        val maxDist = hypot(imgW.toDouble(), imgH.toDouble()).coerceAtLeast(1.0)

        fun bestFor(group: List<MarkerBox>, tx: Double, ty: Double): MarkerBox? =
            group.maxByOrNull { box ->
                val proximity = 1.0 - (hypot(box.center.x - tx, box.center.y - ty) / maxDist)
                    .coerceIn(0.0, 1.0)
                proximity * 0.55 + box.density * 0.20 + box.solidity * 0.15 + box.squareness * 0.10
            }

        return validateAndBuild(
            bestFor(tlCands, 0.0, 0.0),
            bestFor(trCands, imgW.toDouble(), 0.0),
            bestFor(blCands, 0.0, imgH.toDouble()),
            bestFor(brCands, imgW.toDouble(), imgH.toDouble()),
        )
    }

    private fun validateAndBuild(
        tl: MarkerBox?,
        tr: MarkerBox?,
        bl: MarkerBox?,
        br: MarkerBox?,
    ): DetectedMarkers? {
        if (tl == null || tr == null || bl == null || br == null) return null

        val unique = setOf(
            tl.center.x to tl.center.y, tr.center.x to tr.center.y,
            bl.center.x to bl.center.y, br.center.x to br.center.y,
        )
        if (unique.size != 4) return null

        if (tl.center.x >= tr.center.x || bl.center.x >= br.center.x ||
            tl.center.y >= bl.center.y || tr.center.y >= br.center.y
        ) return null

        return DetectedMarkers(tl, tr, bl, br)
    }

    private fun computeSolidity(contour: MatOfPoint): Double {
        val hullIndices = MatOfInt()
        Imgproc.convexHull(contour, hullIndices)
        val contourPoints = contour.toArray()
        val hullPoints = hullIndices.toArray().map { index -> contourPoints[index] }
        val hull = MatOfPoint(*hullPoints.toTypedArray())

        val contourArea = Imgproc.contourArea(contour)
        val hullArea = Imgproc.contourArea(hull)

        hull.release()
        hullIndices.release()

        if (hullArea <= 0.0) {
            return 0.0
        }

        return contourArea / hullArea
    }

    private fun selectCandidate(
        candidates: List<MarkerBox>,
        imgW: Int,
        imgH: Int,
        corner: Corner,
    ): MarkerBox? {
        val maxCornerX = imgW * TemplateConfig.MARKER_CORNER_REGION_FRAC
        val maxCornerY = imgH * TemplateConfig.MARKER_CORNER_REGION_FRAC

        val cornerCandidates = candidates.filter { candidate ->
            when (corner) {
                Corner.TOP_LEFT ->
                    candidate.center.x <= maxCornerX && candidate.center.y <= maxCornerY
                Corner.TOP_RIGHT ->
                    candidate.center.x >= imgW - maxCornerX && candidate.center.y <= maxCornerY
                Corner.BOTTOM_LEFT ->
                    candidate.center.x <= maxCornerX && candidate.center.y >= imgH - maxCornerY
                Corner.BOTTOM_RIGHT ->
                    candidate.center.x >= imgW - maxCornerX && candidate.center.y >= imgH - maxCornerY
            }
        }

        if (cornerCandidates.isEmpty()) {
            return null
        }

        val target = when (corner) {
            Corner.TOP_LEFT -> Point(0.0, 0.0)
            Corner.TOP_RIGHT -> Point(imgW.toDouble(), 0.0)
            Corner.BOTTOM_LEFT -> Point(0.0, imgH.toDouble())
            Corner.BOTTOM_RIGHT -> Point(imgW.toDouble(), imgH.toDouble())
        }
        val maxDistance = hypot(
            maxCornerX.toDouble(),
            maxCornerY.toDouble(),
        ).coerceAtLeast(1.0)

        return cornerCandidates.maxByOrNull { candidate ->
            val distance = hypot(
                candidate.center.x - target.x,
                candidate.center.y - target.y,
            )
            val proximity = 1.0 - (distance / maxDistance).coerceIn(0.0, 1.0)
            val areaScore = (candidate.area / (imgW * imgH * TemplateConfig.MARKER_MAX_AREA_FRAC))
                .coerceIn(0.0, 1.0)
            proximity * 0.55 +
                candidate.density * 0.20 +
                candidate.solidity * 0.15 +
                candidate.squareness * 0.10 +
                areaScore * 0.05 -
                abs(1.0 - candidate.squareness) * 0.05
        }
    }

    private enum class Corner {
        TOP_LEFT,
        TOP_RIGHT,
        BOTTOM_LEFT,
        BOTTOM_RIGHT,
    }
}
