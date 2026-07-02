package net.godevs.thmcampusnav.ar.rendering

import android.opengl.GLES20
import android.opengl.Matrix
import com.google.ar.core.Plane
import com.google.ar.core.TrackingState
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Lightweight, asset-free renderer that fills each detected ARCore plane with a
 * translucent colour and draws its outline. This visualises plane detection
 * without needing the textured PlaneRenderer from the full sample.
 */
class PlaneRenderer {

    private var program = 0
    private var positionAttrib = 0
    private var mvpUniform = 0
    private var colorUniform = 0

    private val modelMatrix = FloatArray(16)
    private val viewProjMatrix = FloatArray(16)
    private val mvpMatrix = FloatArray(16)

    fun createOnGlThread() {
        program = ShaderUtil.createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
        positionAttrib = GLES20.glGetAttribLocation(program, "a_Position")
        mvpUniform = GLES20.glGetUniformLocation(program, "u_ModelViewProjection")
        colorUniform = GLES20.glGetUniformLocation(program, "u_Color")
    }

    fun draw(planes: Collection<Plane>, viewMatrix: FloatArray, projMatrix: FloatArray) {
        Matrix.multiplyMM(viewProjMatrix, 0, projMatrix, 0, viewMatrix, 0)

        GLES20.glUseProgram(program)
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        GLES20.glDepthMask(false)
        GLES20.glEnableVertexAttribArray(positionAttrib)

        for (plane in planes) {
            if (plane.trackingState != TrackingState.TRACKING || plane.subsumedBy != null) {
                continue
            }
            val polygon2d = plane.polygon ?: continue
            polygon2d.rewind()
            val vertexCount = polygon2d.remaining() / 2
            if (vertexCount < 3) continue

            val buffer = ByteBuffer
                .allocateDirect(vertexCount * 3 * FLOAT_SIZE)
                .order(ByteOrder.nativeOrder())
                .asFloatBuffer()
            for (i in 0 until vertexCount) {
                val x = polygon2d.get()
                val z = polygon2d.get()
                buffer.put(x)
                buffer.put(0.0f)
                buffer.put(z)
            }
            buffer.rewind()

            plane.centerPose.toMatrix(modelMatrix, 0)
            Matrix.multiplyMM(mvpMatrix, 0, viewProjMatrix, 0, modelMatrix, 0)
            GLES20.glUniformMatrix4fv(mvpUniform, 1, false, mvpMatrix, 0)
            GLES20.glVertexAttribPointer(
                positionAttrib, 3, GLES20.GL_FLOAT, false, 0, buffer,
            )

            // Translucent fill.
            GLES20.glUniform4f(colorUniform, FILL[0], FILL[1], FILL[2], FILL[3])
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_FAN, 0, vertexCount)

            // Brighter outline.
            GLES20.glUniform4f(colorUniform, LINE[0], LINE[1], LINE[2], LINE[3])
            GLES20.glLineWidth(6.0f)
            GLES20.glDrawArrays(GLES20.GL_LINE_LOOP, 0, vertexCount)
        }

        GLES20.glDisableVertexAttribArray(positionAttrib)
        GLES20.glDepthMask(true)
        GLES20.glDisable(GLES20.GL_BLEND)
    }

    companion object {
        private const val FLOAT_SIZE = 4

        // THM green, translucent.
        private val FILL = floatArrayOf(0.0f, 0.588f, 0.251f, 0.35f)
        private val LINE = floatArrayOf(0.3f, 0.77f, 0.49f, 0.9f)

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
