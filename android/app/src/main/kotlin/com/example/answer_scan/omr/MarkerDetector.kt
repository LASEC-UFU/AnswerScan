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
import kotlin.math.acos
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min

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
        val qualityScore: Double = 0.0,
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

        val byGeometry = selectBestQuadrilateral(candidates, imgW, imgH)
        if (byGeometry != null) {
            Log.d(TAG, "Markers found via quadrilateral search (quality=${byGeometry.qualityScore})")
            return byGeometry
        }

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

    private fun selectBestQuadrilateral(
        candidates: List<MarkerBox>,
        imgW: Int,
        imgH: Int,
    ): DetectedMarkers? {
        var best: DetectedMarkers? = null
        val imageArea = imgW.toDouble() * imgH
        val targetAspect = TemplateConfig.WARP_W.toDouble() / TemplateConfig.WARP_H

        for (a in 0 until candidates.size - 3) {
            for (b in a + 1 until candidates.size - 2) {
                for (c in b + 1 until candidates.size - 1) {
                    for (d in c + 1 until candidates.size) {
                        val group = listOf(candidates[a], candidates[b], candidates[c], candidates[d])
                        val ordered = orderByImageCorners(group) ?: continue
                        val tl = ordered[0]
                        val tr = ordered[1]
                        val bl = ordered[2]
                        val br = ordered[3]

                        val topWidth = distance(tl.center, tr.center)
                        val bottomWidth = distance(bl.center, br.center)
                        val leftHeight = distance(tl.center, bl.center)
                        val rightHeight = distance(tr.center, br.center)
                        val meanWidth = (topWidth + bottomWidth) / 2.0
                        val meanHeight = (leftHeight + rightHeight) / 2.0
                        if (meanHeight <= 0.0) continue

                        val aspect = meanWidth / meanHeight
                        val widthRatio = max(topWidth, bottomWidth) / max(1.0, min(topWidth, bottomWidth))
                        val heightRatio = max(leftHeight, rightHeight) / max(1.0, min(leftHeight, rightHeight))
                        val horizontalAngle = oppositeSideAngle(tl.center, tr.center, bl.center, br.center)
                        val verticalAngle = oppositeSideAngle(tl.center, bl.center, tr.center, br.center)
                        if (aspect !in 0.85..7.0 ||
                            widthRatio > TemplateConfig.MAX_OPPOSITE_SIDE_RATIO ||
                            heightRatio > TemplateConfig.MAX_OPPOSITE_SIDE_RATIO ||
                            horizontalAngle > TemplateConfig.MAX_OPPOSITE_SIDE_ANGLE_DEG ||
                            verticalAngle > TemplateConfig.MAX_OPPOSITE_SIDE_ANGLE_DEG
                        ) continue

                        val polygon = MatOfPoint(tl.center, tr.center, br.center, bl.center)
                        val areaFraction = Imgproc.contourArea(polygon) / imageArea
                        polygon.release()

                        val markerAreas = group.map { it.bounds.area().toDouble() }
                        val sizeSimilarity = markerAreas.minOrNull()!! / markerAreas.maxOrNull()!!
                        val shapeQuality = group.map {
                            (it.density + it.solidity + it.squareness) / 3.0
                        }.average()
                        val aspectQuality = exp(-abs(ln(aspect / targetAspect)))
                        val quality = areaFraction *
                            sizeSimilarity * sizeSimilarity * sizeSimilarity *
                            shapeQuality *
                            aspectQuality

                        if (best == null || quality > best.qualityScore) {
                            best = DetectedMarkers(tl, tr, bl, br, quality)
                        }
                    }
                }
            }
        }
        return best
    }

    private fun orderByImageCorners(group: List<MarkerBox>): List<MarkerBox>? {
        val tl = group.minByOrNull { it.center.x + it.center.y } ?: return null
        val br = group.maxByOrNull { it.center.x + it.center.y } ?: return null
        val tr = group.maxByOrNull { it.center.x - it.center.y } ?: return null
        val bl = group.minByOrNull { it.center.x - it.center.y } ?: return null
        if (setOf(tl, tr, bl, br).size != 4) return null
        return listOf(tl, tr, bl, br)
    }

    private fun distance(a: Point, b: Point): Double = hypot(a.x - b.x, a.y - b.y)

    private fun oppositeSideAngle(a1: Point, a2: Point, b1: Point, b2: Point): Double {
        val ax = a2.x - a1.x
        val ay = a2.y - a1.y
        val bx = b2.x - b1.x
        val by = b2.y - b1.y
        val denominator = hypot(ax, ay) * hypot(bx, by)
        if (denominator <= 0.0) return 180.0
        val cosine = ((ax * bx + ay * by) / denominator).coerceIn(-1.0, 1.0)
        return Math.toDegrees(acos(cosine))
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
