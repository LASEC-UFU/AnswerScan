package com.example.answer_scan.omr

import android.util.Log
import androidx.exifinterface.media.ExifInterface
import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.MatOfDouble
import org.opencv.core.MatOfPoint
import org.opencv.core.Point
import org.opencv.core.Size
import org.opencv.imgcodecs.Imgcodecs
import org.opencv.imgproc.Imgproc
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

            val validation = validateTemplate(
                markers.templateCorners, oriented.width(), oriented.height(),
            )
            if (validation != null) {
                return resultMapper.buildError(
                    message = validation.message,
                    sheetStatus = validation.sheetStatus,
                    markersDetected = 4,
                    extraDebug = mapOf("sharpnessVariance" to sharpnessVariance),
                )
            }

            perspectiveCorrector.warp(blurred, markers.templateCorners, warped)
            val rotated180 = normalizeTemplateOrientation(warped)

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

            val (scores, noiseFloor) = answerReader.scoreAllCells(cleanBinary)
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
                ),
            )

            return if (debugPath != null) result + mapOf("debugImagePath" to debugPath)
            else result

        } finally {
            releaseAll(
                src, oriented, gray, claheGray, blurred,
                markerBinary, otsuBinary,
                warped, claheWarped, warpAdaptive, warpOtsu, warpBinary, cleanBinary,
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
     * Returns a flat list [x0,y0, x1,y1, x2,y2, x3,y3] for TL/TR/BL/BR, or
     * null when no valid set of 4 markers is found.
     */
    fun detectMarkersLive(
        yPlane: ByteArray,
        width: Int,
        height: Int,
        rowStride: Int,
    ): List<Double>? {
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

            val markers = markerDetector.detect(combined, width, height) ?: return null
            return markers.templateCorners.flatMap { listOf(it.x, it.y) }
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
            val lw = TemplateConfig.LABEL_W
            val hh = TemplateConfig.HEADER_H
            val ww = TemplateConfig.WARP_W
            val wh = TemplateConfig.WARP_H
            val top    = bandDensity(binary, lw,      0,       ww - lw, hh)
            val left   = bandDensity(binary, 0,       hh,      lw,      wh - hh)
            val bottom = bandDensity(binary, lw,      wh - hh, ww - lw, hh)
            val right  = bandDensity(binary, ww - lw, hh,      lw,      wh - hh)
            return (top * 1.4 + left * 1.2) - (bottom * 0.7 + right * 0.7)
        } finally {
            binary.release()
        }
    }

    private fun bandDensity(binary: Mat, x: Int, y: Int, width: Int, height: Int): Double {
        val safeX = x.coerceIn(0, binary.cols() - 1)
        val safeY = y.coerceIn(0, binary.rows() - 1)
        val safeW = width.coerceIn(1, binary.cols() - safeX)
        val safeH = height.coerceIn(1, binary.rows() - safeY)
        val roi = binary.submat(safeY, safeY + safeH, safeX, safeX + safeW)
        val density = Core.countNonZero(roi).toDouble() / (safeW * safeH)
        roi.release()
        return density
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

    private fun validateTemplate(corners: List<Point>, imgW: Int, imgH: Int): ValidationFailure? {
        val topWidth    = distance(corners[0], corners[1])
        val bottomWidth = distance(corners[2], corners[3])
        val leftHeight  = distance(corners[0], corners[2])
        val rightHeight = distance(corners[1], corners[3])

        val widthRatio  = max(topWidth,   bottomWidth) / max(1.0, minOf(topWidth,   bottomWidth))
        val heightRatio = max(leftHeight, rightHeight) / max(1.0, minOf(leftHeight, rightHeight))
        if (widthRatio  > TemplateConfig.MAX_OPPOSITE_SIDE_RATIO ||
            heightRatio > TemplateConfig.MAX_OPPOSITE_SIDE_RATIO
        ) {
            return ValidationFailure(
                "Perspectiva forte demais. Reenquadre a folha mais de frente.",
                "perspective_invalid",
            )
        }

        val polygon = MatOfPoint(*corners.toTypedArray())
        val areaFraction = Imgproc.contourArea(polygon) / (imgW.toDouble() * imgH)
        polygon.release()
        if (areaFraction < TemplateConfig.MIN_TEMPLATE_AREA_FRAC) {
            return ValidationFailure(
                "Folha pequena ou cortada. Aproxime mais a camera.",
                "sheet_out_of_frame",
            )
        }
        return null
    }

    private fun distance(a: Point, b: Point): Double {
        val dx = a.x - b.x; val dy = a.y - b.y
        return kotlin.math.sqrt(dx * dx + dy * dy)
    }

    private fun releaseAll(vararg mats: Mat) = mats.forEach { it.release() }

    private data class ValidationFailure(val message: String, val sheetStatus: String)
    private data class DetectionOrientation(
        val markers: MarkerDetector.DetectedMarkers,
        val rotationCode: Int?,
        val rotationDegrees: Int,
    )
}
