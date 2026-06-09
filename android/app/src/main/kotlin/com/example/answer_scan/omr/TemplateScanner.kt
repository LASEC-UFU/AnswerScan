package com.example.answer_scan.omr

import android.util.Log
import androidx.exifinterface.media.ExifInterface
import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.MatOfDouble
import org.opencv.core.Point
import org.opencv.core.Size
import org.opencv.imgcodecs.Imgcodecs
import org.opencv.imgproc.Imgproc
import org.opencv.core.MatOfPoint
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.min

class TemplateScanner {

    companion object {
        private const val TAG = "TemplateScanner"
    }

    private val markerDetector = MarkerDetector()
    private val perspectiveCorrector = PerspectiveCorrector()
    private val gridMapper = GridMapper()
    private val answerReader = AnswerReader(gridMapper)
    private val resultMapper = ScanResultMapper()
    private val debugHelper = OmrDebugHelper()

    fun scan(imagePath: String, debug: Boolean = false): Map<String, Any?> {
        val src          = Mat()
        val oriented     = Mat()
        val gray         = Mat()
        val claheGray    = Mat()
        val blurred      = Mat()
        val markerBinary = Mat()
        val otsuBinary   = Mat()
        val warped       = Mat()
        val claheWarped  = Mat()
        val warpAdaptive = Mat()
        val warpOtsu     = Mat()
        val warpBinary   = Mat()
        val cleanBinary  = Mat()
        val correctedPreview = Mat()

        try {
            val loaded = Imgcodecs.imread(imagePath)
            if (loaded.empty()) {
                loaded.release()
                return resultMapper.buildError(
                    message = "Nao foi possivel carregar a imagem selecionada.",
                    sheetStatus = "image_load_failed",
                )
            }

            applyExifRotation(imagePath, loaded, oriented)
            loaded.release()

            Imgproc.cvtColor(oriented, gray, Imgproc.COLOR_BGR2GRAY)

            val sharpnessVariance = computeSharpnessVariance(gray)
            Log.d(TAG, "Sharpness variance=${"%.2f".format(sharpnessVariance)}")
            if (sharpnessVariance < TemplateConfig.MIN_SHARPNESS_VARIANCE) {
                return resultMapper.buildError(
                    message = "Imagem borrada demais (variancia=${sharpnessVariance.toInt()}). " +
                        "Reposicione a folha e mantenha o celular estavel.",
                    sheetStatus = "blurry",
                    extraDebug = mapOf("sharpnessVariance" to sharpnessVariance),
                )
            }

            // CLAHE normalizes local contrast, making the binary robust against
            // shadows, spotlight effects, and uneven ambient lighting.
            val clahe = Imgproc.createCLAHE(
                TemplateConfig.CLAHE_CLIP_LIMIT,
                Size(TemplateConfig.CLAHE_TILE_GRID.toDouble(), TemplateConfig.CLAHE_TILE_GRID.toDouble()),
            )
            clahe.apply(gray, claheGray)
            Imgproc.GaussianBlur(claheGray, blurred, Size(5.0, 5.0), 0.0)

            Imgproc.adaptiveThreshold(
                blurred, markerBinary, 255.0,
                Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C, Imgproc.THRESH_BINARY_INV, 41, 10.0,
            )
            Imgproc.threshold(
                blurred, otsuBinary, 0.0, 255.0,
                Imgproc.THRESH_BINARY_INV + Imgproc.THRESH_OTSU,
            )
            Core.bitwise_or(markerBinary, otsuBinary, markerBinary)

            val detection = detectBestOrientation(markerBinary)
            val markers = detection?.markers
            if (detection?.rotationCode != null) {
                rotateInPlace(oriented, detection.rotationCode)
                rotateInPlace(blurred, detection.rotationCode)
                rotateInPlace(markerBinary, detection.rotationCode)
            }

            if (markers == null) {
                return resultMapper.buildError(
                    message = "Nao foi possivel localizar os 4 marcadores. " +
                        "Enquadre toda a folha e tente novamente.",
                    sheetStatus = "markers_not_found",
                    extraDebug = mapOf("sharpnessVariance" to sharpnessVariance),
                )
            }

            val geometry = measureGeometry(
                markers.templateCorners,
                oriented.width(),
                oriented.height(),
                markers.qualityScore,
            )
            val validation = validateTemplate(geometry)
            if (validation != null) {
                return resultMapper.buildError(
                    message = validation.message,
                    sheetStatus = validation.sheetStatus,
                    markersDetected = 4,
                    extraDebug = mapOf(
                        "sharpnessVariance" to sharpnessVariance,
                        "geometry" to geometry.toDebugMap(),
                    ),
                )
            }

            perspectiveCorrector.warp(blurred, markers.templateCorners, warped)
            val rotated180 = normalizeTemplateOrientation(warped)
            perspectiveCorrector.warp(oriented, markers.templateCorners, correctedPreview)
            if (rotated180) {
                rotateInPlace(correctedPreview, Core.ROTATE_180)
            }
            val correctedImagePath = imagePath.replace(Regex("\\.[^.]+$"), "_omr_corrected.jpg")
            Imgcodecs.imwrite(correctedImagePath, correctedPreview)

            // Apply CLAHE again on the warped image: a second pass corrects any
            // residual illumination gradient introduced by the perspective warp itself.
            clahe.apply(warped, claheWarped)

            // Adaptive block size proportional to cell dimensions.
            // blockSize ≈ half of the smaller cell axis keeps the neighborhood
            // large enough to span illumination gradients within each cell.
            val cellMin   = min(TemplateConfig.CELL_W, TemplateConfig.CELL_H)
            val rawBlock  = cellMin / 2
            val blockSize = maxOf(if (rawBlock % 2 == 0) rawBlock + 1 else rawBlock, 7)

            Imgproc.adaptiveThreshold(
                claheWarped, warpAdaptive, 255.0,
                Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C, Imgproc.THRESH_BINARY_INV, blockSize, 7.0,
            )
            Imgproc.threshold(
                claheWarped, warpOtsu, 0.0, 255.0,
                Imgproc.THRESH_BINARY_INV + Imgproc.THRESH_OTSU,
            )
            Core.bitwise_or(warpAdaptive, warpOtsu, warpBinary)

            // Morphological opening removes isolated noise pixels (salt noise from
            // compression artefacts, paper texture, etc.) without erasing real marks.
            val openKernel = Imgproc.getStructuringElement(
                Imgproc.MORPH_ELLIPSE,
                Size(TemplateConfig.MORPH_OPEN_SIZE.toDouble(), TemplateConfig.MORPH_OPEN_SIZE.toDouble()),
            )
            Imgproc.morphologyEx(warpBinary, cleanBinary, Imgproc.MORPH_OPEN, openKernel)
            openKernel.release()

            val (scores, noiseFloor) = answerReader.scoreAllCells(warped)
            Log.d(TAG, "Noise floor (P25 cell scores)=${"%.4f".format(noiseFloor)}")
            val classification = resultMapper.classifyAll(scores, noiseFloor)

            val debugPath = if (debug) {
                debugHelper.generate(
                    oriented        = oriented,
                    markerBinary    = markerBinary,
                    templateCorners = markers.templateCorners,
                    warped          = warped,
                    warpBinary      = cleanBinary,
                    scores          = scores,
                    questions       = classification.questions,
                    gridMapper      = gridMapper,
                    originalPath    = imagePath,
                )
            } else null

            val result = resultMapper.buildSuccess(
                questions            = classification.questions,
                markersDetected      = 4,
                perspectiveCorrected = true,
                thresholds           = classification.thresholds,
                extraDebug = mapOf(
                    "sharpnessVariance" to sharpnessVariance,
                    "noiseFloor"        to noiseFloor,
                    "warpBlockSize"     to blockSize,
                    "warpWidth"         to warped.width(),
                    "warpHeight"        to warped.height(),
                    "rotated180"        to rotated180,
                    "detectionRotation" to (detection?.rotationDegrees ?: 0),
                    "markerQuality"     to markers.qualityScore,
                    "geometry"          to geometry.toDebugMap(),
                    "corners"           to markers.templateCorners.map {
                        mapOf("x" to it.x, "y" to it.y)
                    },
                ),
            )

            return result +
                mapOf("correctedImagePath" to correctedImagePath) +
                (if (debugPath != null) mapOf("debugImagePath" to debugPath) else emptyMap())

        } finally {
            releaseAll(
                src, oriented, gray, claheGray, blurred,
                markerBinary, otsuBinary,
                warped, claheWarped, warpAdaptive, warpOtsu, warpBinary, cleanBinary,
                correctedPreview,
            )
        }
    }

    /**
     * Fast marker-only detection for live preview frames.
     *
     * [yPlane]    raw Y (grayscale) plane bytes from Android YUV_420_888
     * [width]     frame width  (sensor native — typically landscape)
     * [height]    frame height
     * [rowStride] bytes per row in [yPlane] (may be >= width due to padding)
     *
     * Returns the same corners and geometry confidence used by the full scan,
     * or null when no valid set of 4 markers is found.
     */
    fun detectMarkersLive(
        yPlane: ByteArray,
        width: Int,
        height: Int,
        rowStride: Int,
    ): Map<String, Any?>? {
        val gray        = Mat()
        val blurred     = Mat()
        val claheBlur   = Mat()
        val adaptive    = Mat()
        val otsuBin     = Mat()
        val combined    = Mat()
        try {
            if (rowStride == width) {
                gray.create(height, width, CvType.CV_8UC1)
                gray.put(0, 0, yPlane)
            } else {
                gray.create(height, width, CvType.CV_8UC1)
                val row = ByteArray(width)
                for (r in 0 until height) {
                    System.arraycopy(yPlane, r * rowStride, row, 0, width)
                    gray.put(r, 0, row)
                }
            }

            Imgproc.GaussianBlur(gray, blurred, Size(5.0, 5.0), 0.0)
            val clahe = Imgproc.createCLAHE(
                TemplateConfig.CLAHE_CLIP_LIMIT,
                Size(TemplateConfig.CLAHE_TILE_GRID.toDouble(), TemplateConfig.CLAHE_TILE_GRID.toDouble()),
            )
            clahe.apply(blurred, claheBlur)

            Imgproc.adaptiveThreshold(
                claheBlur, adaptive, 255.0,
                Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C, Imgproc.THRESH_BINARY_INV, 41, 10.0,
            )
            Imgproc.threshold(
                claheBlur, otsuBin, 0.0, 255.0,
                Imgproc.THRESH_BINARY_INV + Imgproc.THRESH_OTSU,
            )
            Core.bitwise_or(adaptive, otsuBin, combined)

            val detection = detectBestOrientation(combined) ?: return null
            val markers = detection.markers
            val detectedWidth = if (
                detection.rotationCode == Core.ROTATE_90_CLOCKWISE ||
                detection.rotationCode == Core.ROTATE_90_COUNTERCLOCKWISE
            ) height else width
            val detectedHeight = if (
                detection.rotationCode == Core.ROTATE_90_CLOCKWISE ||
                detection.rotationCode == Core.ROTATE_90_COUNTERCLOCKWISE
            ) width else height
            val geometry = measureGeometry(
                markers.templateCorners,
                detectedWidth,
                detectedHeight,
                markers.qualityScore,
            )
            val recoverable = validateTemplate(geometry) == null
            val ready = recoverable && geometry.confidence >= 0.55
            val originalFrameCorners = markers.templateCorners.map {
                pointToOriginalFrame(
                    it,
                    detection.rotationCode,
                    width,
                    height,
                )
            }
            return mapOf(
                "corners" to originalFrameCorners.flatMap { listOf(it.x, it.y) },
                "confidence" to geometry.confidence,
                "state" to if (ready) "ready" else "adjusting",
                "geometry" to geometry.toDebugMap(),
                "rotation" to detection.rotationDegrees,
            )
        } finally {
            releaseAll(gray, blurred, claheBlur, adaptive, otsuBin, combined)
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /**
     * Reads EXIF orientation from [imagePath] and rotates [src] into [dst]
     * so that the pixel data matches the intended viewing orientation.
     * When EXIF is absent or normal, [src] is simply copied to [dst].
     */
    private fun applyExifRotation(imagePath: String, src: Mat, dst: Mat) {
        val rotationCode = try {
            val exif = ExifInterface(imagePath)
            when (exif.getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )) {
                ExifInterface.ORIENTATION_ROTATE_90  -> Core.ROTATE_90_CLOCKWISE
                ExifInterface.ORIENTATION_ROTATE_180 -> Core.ROTATE_180
                ExifInterface.ORIENTATION_ROTATE_270 -> Core.ROTATE_90_COUNTERCLOCKWISE
                else                                 -> null
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not read EXIF: ${e.message}")
            null
        }

        if (rotationCode != null) {
            Core.rotate(src, dst, rotationCode)
        } else {
            src.copyTo(dst)
        }
    }

    /**
     * Checks whether [warped] is upside-down and, if so, rotates it 180° in-place.
     * Returns true if the image was rotated.
     */
    private fun normalizeTemplateOrientation(warped: Mat): Boolean {
        val rotated = Mat()
        try {
            Core.rotate(warped, rotated, Core.ROTATE_180)

            val uprightScore = orientationScore(warped)
            val rotatedScore = orientationScore(rotated)

            val shouldRotate = rotatedScore > uprightScore
            if (shouldRotate) rotated.copyTo(warped)

            Log.d(
                TAG,
                "Orientation scores  upright=${"%.4f".format(uprightScore)} " +
                    "rotated=${"%.4f".format(rotatedScore)}  rotate=$shouldRotate",
            )
            return shouldRotate
        } finally {
            rotated.release()
        }
    }

    private fun orientationScore(gray: Mat): Double {
        val binary = Mat()
        try {
            Imgproc.threshold(
                gray, binary, 0.0, 255.0,
                Imgproc.THRESH_BINARY_INV + Imgproc.THRESH_OTSU,
            )

            var borderDensitySum = 0.0
            var cells = 0
            for (col in 0 until TemplateConfig.N_COLS) {
                for (row in 0 until TemplateConfig.N_ROWS) {
                    val rect = gridMapper.getFullCellRect(col, row)
                    val inset = 7
                    val outer = binary.submat(rect.y1, rect.y2, rect.x1, rect.x2)
                    val inner = binary.submat(
                        rect.y1 + inset,
                        rect.y2 - inset,
                        rect.x1 + inset,
                        rect.x2 - inset,
                    )
                    val borderPixels = outer.rows() * outer.cols() - inner.rows() * inner.cols()
                    if (borderPixels > 0) {
                        val borderInk = Core.countNonZero(outer) - Core.countNonZero(inner)
                        borderDensitySum += borderInk.toDouble() / borderPixels
                        cells++
                    }
                    outer.release()
                    inner.release()
                }
            }
            return if (cells == 0) 0.0 else borderDensitySum / cells
        } finally {
            binary.release()
        }
    }

    private fun computeSharpnessVariance(gray: Mat): Double {
        val lap    = Mat()
        val mean   = MatOfDouble()
        val stdDev = MatOfDouble()
        try {
            Imgproc.Laplacian(gray, lap, CvType.CV_64F)
            Core.meanStdDev(lap, mean, stdDev)
            return stdDev.toArray().firstOrNull()?.pow(2) ?: 0.0
        } finally {
            lap.release(); mean.release(); stdDev.release()
        }
    }

    private fun detectBestOrientation(binary: Mat): DetectionOrientation? {
        val options = listOf(
            null to 0,
            Core.ROTATE_90_CLOCKWISE to 90,
            Core.ROTATE_180 to 180,
            Core.ROTATE_90_COUNTERCLOCKWISE to 270,
        )
        var best: DetectionOrientation? = null

        for ((rotationCode, degrees) in options) {
            val candidateBinary = Mat()
            try {
                if (rotationCode == null) binary.copyTo(candidateBinary)
                else Core.rotate(binary, candidateBinary, rotationCode)

                val markers = markerDetector.detect(
                    candidateBinary,
                    candidateBinary.width(),
                    candidateBinary.height(),
                ) ?: continue
                val candidate = DetectionOrientation(markers, rotationCode, degrees)
                if (best == null || markers.qualityScore > best.markers.qualityScore) {
                    best = candidate
                }
            } finally {
                candidateBinary.release()
            }
        }
        return best
    }

    private fun rotateInPlace(mat: Mat, rotationCode: Int) {
        val rotated = Mat()
        Core.rotate(mat, rotated, rotationCode)
        rotated.copyTo(mat)
        rotated.release()
    }

    private fun pointToOriginalFrame(
        point: Point,
        rotationCode: Int?,
        originalWidth: Int,
        originalHeight: Int,
    ): Point = when (rotationCode) {
        Core.ROTATE_90_CLOCKWISE -> Point(
            point.y,
            originalHeight - 1.0 - point.x,
        )
        Core.ROTATE_180 -> Point(
            originalWidth - 1.0 - point.x,
            originalHeight - 1.0 - point.y,
        )
        Core.ROTATE_90_COUNTERCLOCKWISE -> Point(
            originalWidth - 1.0 - point.y,
            point.x,
        )
        else -> point
    }

    private fun validateTemplate(geometry: GeometryDiagnostics): ValidationFailure? {
        if (geometry.areaFraction < TemplateConfig.MIN_TEMPLATE_AREA_FRAC ||
            geometry.minSidePx < 30.0
        ) {
            return ValidationFailure(
                "Nao foi possivel reconstruir a geometria da folha. Inclua os quatro marcadores na imagem.",
                "perspective_invalid",
            )
        }
        return null
    }

    private fun measureGeometry(
        corners: List<Point>,
        imageWidth: Int,
        imageHeight: Int,
        markerQuality: Double,
    ): GeometryDiagnostics {
        val topWidth = distance(corners[0], corners[1])
        val bottomWidth = distance(corners[2], corners[3])
        val leftHeight = distance(corners[0], corners[2])
        val rightHeight = distance(corners[1], corners[3])
        val widthRatio = max(topWidth, bottomWidth) / max(1.0, minOf(topWidth, bottomWidth))
        val heightRatio = max(leftHeight, rightHeight) / max(1.0, minOf(leftHeight, rightHeight))
        val horizontalAngle = oppositeSideAngle(corners[0], corners[1], corners[2], corners[3])
        val verticalAngle = oppositeSideAngle(corners[0], corners[2], corners[1], corners[3])
        val polygon = MatOfPoint(corners[0], corners[1], corners[3], corners[2])
        val areaFraction = Imgproc.contourArea(polygon) /
            (imageWidth.toDouble() * imageHeight.toDouble()).coerceAtLeast(1.0)
        polygon.release()
        val distortion = max(widthRatio, heightRatio)
        val angle = max(horizontalAngle, verticalAngle)
        val confidence = (
            (1.0 / distortion).coerceIn(0.0, 1.0) * 0.45 +
                (1.0 - angle / 90.0).coerceIn(0.0, 1.0) * 0.35 +
                (areaFraction / 0.25).coerceIn(0.0, 1.0) * 0.15 +
                markerQuality.coerceIn(0.0, 1.0) * 0.05
            ).coerceIn(0.0, 1.0)
        return GeometryDiagnostics(
            widthRatio, heightRatio, horizontalAngle, verticalAngle,
            areaFraction, listOf(topWidth, bottomWidth, leftHeight, rightHeight).minOrNull() ?: 0.0,
            confidence,
        )
    }

    private fun oppositeSideAngle(a1: Point, a2: Point, b1: Point, b2: Point): Double {
        val ax = a2.x - a1.x
        val ay = a2.y - a1.y
        val bx = b2.x - b1.x
        val by = b2.y - b1.y
        val denominator = kotlin.math.hypot(ax, ay) * kotlin.math.hypot(bx, by)
        if (denominator <= 0.0) return 180.0
        val cosine = ((ax * bx + ay * by) / denominator).coerceIn(-1.0, 1.0)
        return Math.toDegrees(kotlin.math.acos(cosine))
    }

    private fun distance(a: Point, b: Point): Double {
        val dx = a.x - b.x; val dy = a.y - b.y
        return kotlin.math.sqrt(dx * dx + dy * dy)
    }

    private fun releaseAll(vararg mats: Mat) = mats.forEach { it.release() }

    private data class ValidationFailure(val message: String, val sheetStatus: String)
    private data class GeometryDiagnostics(
        val widthRatio: Double,
        val heightRatio: Double,
        val horizontalAngle: Double,
        val verticalAngle: Double,
        val areaFraction: Double,
        val minSidePx: Double,
        val confidence: Double,
    ) {
        fun toDebugMap(): Map<String, Double> = mapOf(
            "widthRatio" to widthRatio,
            "heightRatio" to heightRatio,
            "horizontalAngle" to horizontalAngle,
            "verticalAngle" to verticalAngle,
            "areaFraction" to areaFraction,
            "minSidePx" to minSidePx,
            "perspectiveConfidence" to confidence,
        )
    }
    private data class DetectionOrientation(
        val markers: MarkerDetector.DetectedMarkers,
        val rotationCode: Int?,
        val rotationDegrees: Int,
    )
}
