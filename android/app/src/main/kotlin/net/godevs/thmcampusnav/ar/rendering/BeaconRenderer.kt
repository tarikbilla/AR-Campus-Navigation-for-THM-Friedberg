package net.godevs.thmcampusnav.ar.rendering

import android.opengl.GLES20
import android.opengl.Matrix
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.cos
import kotlin.math.sin

/**
 * Renders a glowing vertical "beacon" pillar at the destination building so the
 * user can spot the target while looking around in AR.
 */
class BeaconRenderer {

    private var program = 0
    private var positionAttrib = 0
    private var fracAttrib = 0
    private var mvpUniform = 0
    private var phaseUniform = 0
    private var colorUniform = 0

    private lateinit var posBuffer: FloatBuffer
    private lateinit var fracBuffer: FloatBuffer
    private var vertexCount = 0

    private val model = FloatArray(16)
    private val mvp = FloatArray(16)

    fun createOnGlThread() {
        program = ShaderUtil.createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
        positionAttrib = GLES20.glGetAttribLocation(program, "a_Position")
        fracAttrib = GLES20.glGetAttribLocation(program, "a_Frac")
        mvpUniform = GLES20.glGetUniformLocation(program, "u_ModelViewProjection")
        phaseUniform = GLES20.glGetUniformLocation(program, "u_Phase")
        colorUniform = GLES20.glGetUniformLocation(program, "u_Color")
        buildCylinder()
    }

    private fun buildCylinder() {
        val segments = 24
        val radius = 0.5f
        val height = 5.0f
        val pos = ArrayList<Float>()
        val frac = ArrayList<Float>()
        for (i in 0..segments) {
            val a = (i.toFloat() / segments) * (2.0 * Math.PI).toFloat()
            val x = radius * cos(a)
            val z = radius * sin(a)
            pos.add(x); pos.add(0f); pos.add(z); frac.add(0f)
            pos.add(x); pos.add(height); pos.add(z); frac.add(1f)
        }
        vertexCount = frac.size
        posBuffer = toBuffer(pos)
        fracBuffer = toBuffer(frac)
    }

    private fun toBuffer(data: List<Float>): FloatBuffer {
        val fb = ByteBuffer
            .allocateDirect(data.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
        for (v in data) fb.put(v)
        fb.rewind()
        return fb
    }

    fun draw(x: Float, y: Float, z: Float, viewProj: FloatArray, phase: Float) {
        Matrix.setIdentityM(model, 0)
        Matrix.translateM(model, 0, x, y, z)
        Matrix.multiplyMM(mvp, 0, viewProj, 0, model, 0)

        GLES20.glUseProgram(program)
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE)  // additive glow
        GLES20.glDepthMask(false)

        GLES20.glUniformMatrix4fv(mvpUniform, 1, false, mvp, 0)
        GLES20.glUniform1f(phaseUniform, phase)
        GLES20.glUniform4f(colorUniform, 0.10f, 0.75f, 1.0f, 1.0f)

        posBuffer.rewind()
        fracBuffer.rewind()
        GLES20.glEnableVertexAttribArray(positionAttrib)
        GLES20.glVertexAttribPointer(positionAttrib, 3, GLES20.GL_FLOAT, false, 0, posBuffer)
        GLES20.glEnableVertexAttribArray(fracAttrib)
        GLES20.glVertexAttribPointer(fracAttrib, 1, GLES20.GL_FLOAT, false, 0, fracBuffer)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, vertexCount)

        GLES20.glDisableVertexAttribArray(positionAttrib)
        GLES20.glDisableVertexAttribArray(fracAttrib)
        GLES20.glDepthMask(true)
        GLES20.glDisable(GLES20.GL_BLEND)
    }

    companion object {
        private const val VERTEX_SHADER = """
            uniform mat4 u_ModelViewProjection;
            attribute vec4 a_Position;
            attribute float a_Frac;
            varying float v_Frac;
            void main() {
                v_Frac = a_Frac;
                gl_Position = u_ModelViewProjection * a_Position;
            }
        """

        // Fades toward the top; a travelling pulse rises up the pillar.
        private const val FRAGMENT_SHADER = """
            precision mediump float;
            uniform vec4 u_Color;
            uniform float u_Phase;
            varying float v_Frac;
            void main() {
                float fade = 1.0 - v_Frac;
                float rise = fract(v_Frac - u_Phase * 0.5);
                float pulse = smoothstep(0.7, 1.0, rise);
                float a = u_Color.a * (0.25 + 0.6 * fade + 0.4 * pulse);
                gl_FragColor = vec4(u_Color.rgb, a);
            }
        """
    }
}
