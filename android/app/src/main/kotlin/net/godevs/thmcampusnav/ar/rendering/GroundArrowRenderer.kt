package net.godevs.thmcampusnav.ar.rendering

import android.opengl.GLES20
import android.opengl.Matrix
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * Renders flat 3D direction arrows that lie on the detected ground plane and
 * point along the route. Each arrow is drawn from the same geometry via a model
 * matrix (translate + rotate about the vertical axis), so a series of them can
 * be placed along the path with a flowing highlight.
 */
class GroundArrowRenderer {

    private var program = 0
    private var positionAttrib = 0
    private var mvpUniform = 0
    private var colorUniform = 0

    private lateinit var buffer: FloatBuffer
    private var vertexCount = 0

    private val model = FloatArray(16)
    private val mvp = FloatArray(16)

    fun createOnGlThread() {
        program = ShaderUtil.createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
        positionAttrib = GLES20.glGetAttribLocation(program, "a_Position")
        mvpUniform = GLES20.glGetUniformLocation(program, "u_ModelViewProjection")
        colorUniform = GLES20.glGetUniformLocation(program, "u_Color")
        buildArrow()
    }

    private fun buildArrow() {
        // A solid arrow lying on the XZ plane (y=0), pointing toward local +Z.
        val v = floatArrayOf(
            // arrowhead (triangle)
            0.0f, 0.0f, 0.55f,
            -0.42f, 0.0f, 0.08f,
            0.42f, 0.0f, 0.08f,
            // shaft (two triangles)
            -0.15f, 0.0f, 0.08f,
            0.15f, 0.0f, 0.08f,
            0.15f, 0.0f, -0.5f,
            -0.15f, 0.0f, 0.08f,
            0.15f, 0.0f, -0.5f,
            -0.15f, 0.0f, -0.5f,
        )
        vertexCount = v.size / 3
        buffer = ByteBuffer
            .allocateDirect(v.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
        buffer.put(v)
        buffer.rewind()
    }

    /**
     * @param headingDeg rotation about the vertical axis so local +Z aligns with
     *   the route direction (degrees).
     */
    fun draw(
        x: Float,
        y: Float,
        z: Float,
        headingDeg: Float,
        viewProj: FloatArray,
        r: Float,
        g: Float,
        b: Float,
        a: Float,
    ) {
        Matrix.setIdentityM(model, 0)
        Matrix.translateM(model, 0, x, y, z)
        Matrix.rotateM(model, 0, headingDeg, 0f, 1f, 0f)
        Matrix.multiplyMM(mvp, 0, viewProj, 0, model, 0)

        GLES20.glUseProgram(program)
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        GLES20.glDepthMask(false)

        GLES20.glUniformMatrix4fv(mvpUniform, 1, false, mvp, 0)
        GLES20.glUniform4f(colorUniform, r, g, b, a)

        buffer.rewind()
        GLES20.glEnableVertexAttribArray(positionAttrib)
        GLES20.glVertexAttribPointer(positionAttrib, 3, GLES20.GL_FLOAT, false, 0, buffer)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLES, 0, vertexCount)
        GLES20.glDisableVertexAttribArray(positionAttrib)

        GLES20.glDepthMask(true)
        GLES20.glDisable(GLES20.GL_BLEND)
    }

    companion object {
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
