package com.example.answer_scan.omr

import org.junit.Assert.assertEquals
import org.junit.Test

class ScanResultMapperTest {

    private val mapper = ScanResultMapper()

    @Test
    fun strongAnswerWithSecondaryNoiseIsNotMultiple() {
        val scores = scoresForFirstQuestion(0.88, 0.59, 0.08, 0.07, 0.06)

        val result = mapper.classifyAll(scores).questions.first()

        assertEquals("A", result.answer)
    }

    @Test
    fun twoStrongAnswersAreMultiple() {
        val scores = scoresForFirstQuestion(0.88, 0.72, 0.08, 0.07, 0.06)

        val result = mapper.classifyAll(scores).questions.first()

        assertEquals("MULTIPLA", result.answer)
    }

    private fun scoresForFirstQuestion(vararg firstQuestion: Double): Array<DoubleArray> =
        Array(TemplateConfig.N_COLS) { column ->
            if (column == 0) firstQuestion
            else doubleArrayOf(0.88, 0.08, 0.07, 0.06, 0.05)
        }
}
