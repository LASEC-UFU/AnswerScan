package com.example.answer_scan.omr

class ScanResultMapper {

    companion object {
        private const val ANSWER_BLANK = "EM_BRANCO"
        private const val ANSWER_MULTIPLE = "MULTIPLA"
        private const val ANSWER_UNCERTAIN = "INCERTA"
    }

    data class QuestionResult(
        val answer: String,
        val confidence: Double,
        val scores: DoubleArray,
    )

    data class ThresholdSet(
        val blank: Double,
        val fill: Double,
        val multiple: Double,
    )

    data class ClassificationBatch(
        val questions: List<QuestionResult>,
        val thresholds: ThresholdSet,
    )

    /**
     * Classifies all 20 questions using adaptive thresholds derived from [noiseFloor].
     *
     * [noiseFloor] is the P25 of all cell scores (from AnswerReader.scoreAllCells).
     * When > 0.005 it is used to compute per-image blank/fill/multiple thresholds,
     * clamped within ±60% of the static defaults so extreme values can't cause harm.
     * A noiseFloor of 0.0 falls back to the static TemplateConfig values.
     */
    fun classifyAll(scores: Array<DoubleArray>, noiseFloor: Double = 0.0): ClassificationBatch {
        val thresholds = resolveThresholds(noiseFloor)
        val questions = (0 until TemplateConfig.N_COLS).map { col ->
            classify(scores[col], thresholds.blank, thresholds.fill, thresholds.multiple)
        }
        return ClassificationBatch(questions, thresholds)
    }

    fun buildSuccess(
        questions: List<QuestionResult>,
        markersDetected: Int,
        perspectiveCorrected: Boolean,
        thresholds: ThresholdSet,
        extraDebug: Map<String, Any?> = emptyMap(),
    ): Map<String, Any?> {
        val answers = mutableMapOf<String, String>()
        val confidence = mutableMapOf<String, Double>()
        val scores = mutableMapOf<String, List<Double>>()
        val questionsPayload = mutableMapOf<String, Map<String, Any?>>()

        questions.forEachIndexed { index, question ->
            val key = "${index + 1}"
            answers[key] = question.answer
            confidence[key] = question.confidence
            scores[key] = question.scores.toList()
            questionsPayload[key] = mapOf(
                "resposta" to question.answer,
                "confianca" to question.confidence,
                "preenchimentos" to TemplateConfig.OPTION_LABELS.mapIndexed { optionIndex, label ->
                    label to question.scores.getOrElse(optionIndex) { 0.0 }
                }.toMap(),
            )
        }

        val status = inferStatus(questions)
        val message = when (status) {
            "OK" -> "Cartao lido com sucesso"
            else -> "Leitura concluida com itens para revisao manual"
        }

        return mapOf(
            "success" to true,
            "status" to status,
            "mensagem" to message,
            "questoes" to questionsPayload,
            "sheetStatus" to inferSheetStatus(questions),
            "answers" to answers,
            "confidence" to confidence,
            "scores" to scores,
            "debug" to (mutableMapOf<String, Any?>(
                "markersDetected" to markersDetected,
                "perspectiveCorrected" to perspectiveCorrected,
                "thresholds" to mapOf(
                    "blank" to thresholds.blank,
                    "fill" to thresholds.fill,
                    "multiple" to thresholds.multiple,
                ),
            ).apply {
                putAll(extraDebug)
            }),
        )
    }

    fun buildError(
        message: String,
        sheetStatus: String,
        markersDetected: Int = 0,
        perspectiveCorrected: Boolean = false,
        extraDebug: Map<String, Any?> = emptyMap(),
    ): Map<String, Any?> = mapOf(
        "success" to false,
        "status" to "ERRO",
        "mensagem" to message,
        "sheetStatus" to sheetStatus,
        "error" to message,
        "debug" to (mutableMapOf<String, Any?>(
            "markersDetected" to markersDetected,
            "perspectiveCorrected" to perspectiveCorrected,
        ).apply {
            putAll(extraDebug)
        }),
    )

    private fun classify(
        rowScores: DoubleArray,
        blankThresh: Double = TemplateConfig.BLANK_THRESHOLD,
        fillThresh: Double  = TemplateConfig.FILL_THRESHOLD,
        multiThresh: Double = TemplateConfig.MULTIPLE_THRESHOLD,
    ): QuestionResult {
        val ranked      = rowScores.withIndex().sortedByDescending { it.value }
        val best        = ranked[0]
        val second      = ranked.getOrElse(1) { ranked[0] }
        val bestScore   = best.value
        val secondScore = second.value
        val gap         = bestScore - secondScore
        val ratio       = if (secondScore <= 0.001) Double.MAX_VALUE else bestScore / secondScore

        if (bestScore < blankThresh ||
            (gap < TemplateConfig.DOMINANCE_DELTA && secondScore < multiThresh)
        ) {
            val confidence = 1.0 - (bestScore / blankThresh).coerceIn(0.0, 1.0)
            return QuestionResult(ANSWER_BLANK, confidence, rowScores)
        }

        // Two clearly filled options always invalidate the question, even when
        // one mark is darker than the other.
        if (secondScore >= multiThresh) {
            val confidence = ((bestScore + secondScore) / 2.0).coerceIn(0.0, 1.0)
            return QuestionResult(ANSWER_MULTIPLE, confidence, rowScores)
        }

        if (bestScore < fillThresh ||
            gap < TemplateConfig.DOMINANCE_DELTA ||
            ratio < TemplateConfig.GAP_RATIO
        ) {
            val gapConf   = (gap / TemplateConfig.DOMINANCE_DELTA).coerceIn(0.0, 1.0)
            val ratioConf = (ratio / TemplateConfig.GAP_RATIO).coerceIn(0.0, 1.0)
            val confidence = ((gapConf + ratioConf) / 2.0).coerceIn(0.0, 1.0)
            return QuestionResult(ANSWER_UNCERTAIN, confidence, rowScores)
        }

        val absoluteConf    = ((bestScore - fillThresh) / (1.0 - fillThresh)).coerceIn(0.0, 1.0)
        val separationConf  = (gap / bestScore.coerceAtLeast(0.001)).coerceIn(0.0, 1.0)
        val confidence      = (absoluteConf * 0.45 + separationConf * 0.55).coerceIn(0.0, 1.0)

        return QuestionResult(TemplateConfig.OPTION_LABELS[best.index], confidence, rowScores)
    }

    private fun resolveThresholds(noiseFloor: Double): ThresholdSet {
        return ThresholdSet(
            blank = TemplateConfig.BLANK_THRESHOLD,
            fill = TemplateConfig.FILL_THRESHOLD,
            multiple = TemplateConfig.MULTIPLE_THRESHOLD,
        )
    }

    private fun inferStatus(questions: List<QuestionResult>): String =
        if (questions.any { it.answer == ANSWER_BLANK || it.answer == ANSWER_MULTIPLE || it.answer == ANSWER_UNCERTAIN }) {
            "REVISAO_MANUAL"
        } else {
            "OK"
        }

    private fun inferSheetStatus(questions: List<QuestionResult>): String =
        if (questions.any { question ->
                question.answer == ANSWER_BLANK ||
                    question.answer == ANSWER_MULTIPLE ||
                    question.answer == ANSWER_UNCERTAIN
            }
        ) {
            "review_required"
        } else {
            "ok"
        }
}
