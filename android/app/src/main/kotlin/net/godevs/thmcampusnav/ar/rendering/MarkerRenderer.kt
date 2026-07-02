package net.godevs.thmcampusnav.ar.rendering

import android.opengl.GLES20
import android.opengl.Matrix
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.cos
import kotlin.math.sin

/**
 * Draws a world-anchored "target" marker (a glowing disc lying on the detected
 * plane) at a given anchor pose. Demonstrates real ARCore world anchoring.
 */
class MarkerRenderer {

    private var program = 0
    private var positionAttrib = 0
    private var mvpUniform = 0
    private var colorUniform = 0

    private val mvpMatrix = FloatArray(16)
    private val viewProjMatrix = FloatArray(16)

    private lateinit var discBuffer: FloatBuffer
    private lateinit var ringBuffer: FloatBuffer
    private var discVertexCount = 0
    private var ringVertexCount = 0

    fun createOnGlThread() {
        program = ShaderUtil.createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
        positionAttrib = GLES20.glGetAttribLocation(program, "a_Position")
        mvpUniform = GLES20.glGetUniformLocation(program, "u_ModelViewProjection")
        colorUniform = GLES20.glGetUniformLocation(program, "u_Color")
        buildGeometry()
    }

    private fun buildGeometry() {
        val segments = 40
        val radius = 0.22f

        // Filled disc as a triangle fan: centre + perimeter + closing vertex.
        val disc = ArrayList<Float>()
        disc.add(0f); disc.add(0.01f); disc.add(0f)
        for (i in 0..segments) {
            val a = (i.toFloat() / segments) * (2.0 * Math.PI).toFloat()
            disc.add(radius * cos(a)); disc.add(0.01f); disc.add(radius * sin(a))
        }
        discVertexCount = disc.size / 3
        discBuffer = toBuffer(disc)

        // Outline ring.
        val ring = ArrayList<Float>()
        for (i in 0..segments) {
            val a = (i.toFloat() / segments) * (2.0 * Math.PI).toFloat()
            ring.add(radius * cos(a)); ring.add(0.01f); ring.add(radius * sin(a))
        }
        ringVertexCount = ring.size / 3
        ringBuffer = toBuffer(ring)
    }

    private fun toBuffer(data: List<Float>): FloatBuffer {
        val fb = ByteBuffer
            .allocateDirect(data.size * FLOAT_SIZE)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
        for (v in data) fb.put(v)
        fb.rewind()
        return fb
    }

    fun draw(modelMatrix: FloatArray, viewMatrix: FloatArray, projMatrix: FloatArray) {
        Matrix.multiplyMM(viewProjMatrix, 0, projMatrix, 0, viewMatrix, 0)
        Matrix.multiplyMM(mvpMatrix, 0, viewProjMatrix, 0, modelMatrix, 0)

        GLES20.glUseProgram(program)
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        GLES20.glDepthMask(false)
        GLES20.glEnableVertexAttribArray(positionAttrib)
        GLES20.glUniformMatrix4fv(mvpUniform, 1, false, mvpMatrix, 0)

        discBuffer.rewind()
        GLES20.glVertexAttribPointer(
            positionAttrib, 3, GLES20.GL_FLOAT, false, 0, discBuffer,
        )
        GLES20.glUniform4f(colorUniform, 0.06f, 0.61f, 0.95f, 0.55f)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_FAN, 0, discVertexCount)

        ringBuffer.rewind()
        GLES20.glVertexAttribPointer(
            positionAttrib, 3, GLES20.GL_FLOAT, false, 0, ringBuffer,
        )
        GLES20.glUniform4f(colorUniform, 1.0f, 1.0f, 1.0f, 0.95f)
        GLES20.glLineWidth(8.0f)
        GLES20.glDrawArrays(GLES20.GL_LINE_LOOP, 0, ringVertexCount)

        GLES20.glDisableVertexAttribArray(positionAttrib)
        GLES20.glDepthMask(true)
        GLES20.glDisable(GLES20.GL_BLEND)
    }

    companion object {
        private const val FLOAT_SIZE = 4

        private const val VERTEX_SHADER = """
            uniform mat4 u_ModelViewProjection;
            attribute vec4 a_Position;
            void main() {
                gl_Position = u_ModelViewProjection * a_Position;
            }
        """

        private const val FRAGMENT_SHADER = """
            precision mediump float;
            uniform vec4 u_Color;
            void main() {
                gl_FragColor = u_Color;
            }
        """
    }
}
