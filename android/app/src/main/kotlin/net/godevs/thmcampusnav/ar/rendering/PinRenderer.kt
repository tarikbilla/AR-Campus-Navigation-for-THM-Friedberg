package net.godevs.thmcampusnav.ar.rendering

import android.opengl.GLES20
import android.opengl.Matrix
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.cos
import kotlin.math.sin

/**
 * A 3D "map pin" (a ball on a downward-pointing cone) that hovers over the
 * destination direction, so the user can see which way the target building is.
 * It bobs and pulses gently and is shaded top-bright / bottom-dark for a solid
 * 3D look. Geometry points its tip toward −Y (down); the model matrix places
 * the tip at the target and adds the hover bob.
 */
class PinRenderer {

    private var program = 0
    private var positionAttrib = 0
    private var fracAttrib = 0
    private var mvpUniform = 0
    private var colorUniform = 0
    private var phaseUniform = 0

    private lateinit var buffer: FloatBuffer
    private var vertexCount = 0
    private var maxY = 1f

    private val model = FloatArray(16)
    private val mvp = FloatArray(16)

    fun createOnGlThread() {
        program = ShaderUtil.createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
        positionAttrib = GLES20.glGetAttribLocation(program, "a_Position")
        fracAttrib = GLES20.glGetAttribLocation(program, "a_Frac")
        mvpUniform = GLES20.glGetUniformLocation(program, "u_ModelViewProjection")
        colorUniform = GLES20.glGetUniformLocation(program, "u_Color")
        phaseUniform = GLES20.glGetUniformLocation(program, "u_Phase")
        build()
    }

    private fun build() {
        val coneH = 0.62f
        val coneR = 0.34f
        val ballR = 0.42f
        val ballCy = coneH + 0.26f
        maxY = ballCy + ballR
        val slices = 18
        val stacks = 12

        val data = ArrayList<Float>()
        fun v(x: Float, y: Float, z: Float) {
            data.add(x); data.add(y); data.add(z); data.add(y / maxY)
        }

        // Cone: apex (tip) at origin, opening up to a ring — points downward.
        for (i in 0 until slices) {
            val a0 = (i.toFloat() / slices) * (2.0 * Math.PI).toFloat()
            val a1 = ((i + 1).toFloat() / slices) * (2.0 * Math.PI).toFloat()
            v(0f, 0f, 0f)
            v(coneR * cos(a0), coneH, coneR * sin(a0))
            v(coneR * cos(a1), coneH, coneR * sin(a1))
        }

        // Ball (UV sphere) sitting on top of the cone.
        for (st in 0 until stacks) {
            val p0 = (Math.PI * st / stacks - Math.PI / 2).toFloat()
            val p1 = (Math.PI * (st + 1) / stacks - Math.PI / 2).toFloat()
            for (sl in 0 until slices) {
                val t0 = (2.0 * Math.PI * sl / slices).toFloat()
                val t1 = (2.0 * Math.PI * (sl + 1) / slices).toFloat()
                val v00 = sphere(p0, t0, ballR, ballCy)
                val v10 = sphere(p1, t0, ballR, ballCy)
                val v11 = sphere(p1, t1, ballR, ballCy)
                val v01 = sphere(p0, t1, ballR, ballCy)
                v(v00[0], v00[1], v00[2]); v(v10[0], v10[1], v10[2]); v(v11[0], v11[1], v11[2])
                v(v00[0], v00[1], v00[2]); v(v11[0], v11[1], v11[2]); v(v01[0], v01[1], v01[2])
            }
        }

        vertexCount = data.size / 4
        buffer = ByteBuffer
            .allocateDirect(data.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
        for (f in data) buffer.put(f)
        buffer.rewind()
    }

    private fun sphere(phi: Float, theta: Float, r: Float, cy: Float): FloatArray {
        return floatArrayOf(
            r * cos(phi) * cos(theta),
            cy + r * sin(phi),
            r * cos(phi) * sin(theta),
        )
    }

    /**
     * @param tipX/tipZ world position the pin points at
     * @param groundY ground height; the pin tip hovers a little above it
     * @param scale metres tall multiplier
     */
    fun draw(
        tipX: Float,
        groundY: Float,
        tipZ: Float,
        viewProj: FloatArray,
        phase: Float,
        scale: Float,
        r: Float,
        g: Float,
        b: Float,
    ) {
        val bob = 0.10f * sin(phase * 2.2f)
        Matrix.setIdentityM(model, 0)
        Matrix.translateM(model, 0, tipX, groundY + 1.5f + bob, tipZ)
        Matrix.scaleM(model, 0, scale, scale, scale)
        Matrix.multiplyMM(mvp, 0, viewProj, 0, model, 0)

        GLES20.glUseProgram(program)
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        GLES20.glEnable(GLES20.GL_DEPTH_TEST)
        GLES20.glDepthMask(true)

        GLES20.glUniformMatrix4fv(mvpUniform, 1, false, mvp, 0)
        GLES20.glUniform4f(colorUniform, r, g, b, 1.0f)
        GLES20.glUniform1f(phaseUniform, phase)

        buffer.rewind()
        buffer.position(0)
        GLES20.glEnableVertexAttribArray(positionAttrib)
        GLES20.glVertexAttribPointer(positionAttrib, 3, GLES20.GL_FLOAT, false, 4 * 4, buffer)
        buffer.position(3)
        GLES20.glEnableVertexAttribArray(fracAttrib)
        GLES20.glVertexAttribPointer(fracAttrib, 1, GLES20.GL_FLOAT, false, 4 * 4, buffer)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLES, 0, vertexCount)

        GLES20.glDisableVertexAttribArray(positionAttrib)
        GLES20.glDisableVertexAttribArray(fracAttrib)
        GLES20.glDisable(GLES20.GL_DEPTH_TEST)
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

        // Top-bright / bottom-dark shading plus a soft pulse for a lively pin.
        private const val FRAGMENT_SHADER = """
            precision mediump float;
            uniform vec4 u_Color;
            uniform float u_Phase;
            varying float v_Frac;
            void main() {
                float shade = 0.55 + 0.45 * v_Frac;
                float pulse = 0.85 + 0.15 * sin(u_Phase * 3.0);
                gl_FragColor = vec4(u_Color.rgb * shade * pulse, u_Color.a);
            }
        """
    }
}
