package net.godevs.thmcampusnav.ar.rendering

import android.opengl.GLES20
import android.opengl.Matrix
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * Renders a solid **3D chevron** (an extruded arrow with a bright top, shaded
 * side walls and a darker base) that sits on the ground and points along the
 * route. A series of them is placed just ahead of the user and animated with a
 * flowing highlight, giving a clear "walk this way" cue with real depth.
 */
class GroundArrowRenderer {

    private var program = 0
    private var positionAttrib = 0
    private var shadeAttrib = 0
    private var mvpUniform = 0
    private var colorUniform = 0

    private lateinit var buffer: FloatBuffer
    private var vertexCount = 0

    private val model = FloatArray(16)
    private val mvp = FloatArray(16)

    fun createOnGlThread() {
        program = ShaderUtil.createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
        positionAttrib = GLES20.glGetAttribLocation(program, "a_Position")
        shadeAttrib = GLES20.glGetAttribLocation(program, "a_Shade")
        mvpUniform = GLES20.glGetUniformLocation(program, "u_ModelViewProjection")
        colorUniform = GLES20.glGetUniformLocation(program, "u_Color")
        buildChevron()
    }

    private fun buildChevron() {
        // Arrow outline in the local XZ plane (points toward +Z), extruded up.
        val outline = arrayOf(
            floatArrayOf(0.00f, 0.60f), // tip
            floatArrayOf(0.42f, 0.12f),
            floatArrayOf(0.17f, 0.12f),
            floatArrayOf(0.17f, -0.45f),
            floatArrayOf(-0.17f, -0.45f),
            floatArrayOf(-0.17f, 0.12f),
            floatArrayOf(-0.42f, 0.12f),
        )
        val h = 0.15f // extrusion height (metres)
        val data = ArrayList<Float>()
        fun vert(x: Float, y: Float, z: Float, shade: Float) {
            data.add(x); data.add(y); data.add(z); data.add(shade)
        }

        // Top face (bright), fan from the tip.
        for (i in 1 until outline.size - 1) {
            val a = outline[0]; val b = outline[i]; val c = outline[i + 1]
            vert(a[0], h, a[1], 1.0f)
            vert(b[0], h, b[1], 1.0f)
            vert(c[0], h, c[1], 1.0f)
        }
        // Bottom face (dark), fan from the tip (reverse order).
        for (i in 1 until outline.size - 1) {
            val a = outline[0]; val b = outline[i]; val c = outline[i + 1]
            vert(a[0], 0f, a[1], 0.4f)
            vert(c[0], 0f, c[1], 0.4f)
            vert(b[0], 0f, b[1], 0.4f)
        }
        // Side walls (mid shade) around the perimeter.
        for (i in outline.indices) {
            val p = outline[i]
            val q = outline[(i + 1) % outline.size]
            vert(p[0], 0f, p[1], 0.65f)
            vert(q[0], 0f, q[1], 0.65f)
            vert(q[0], h, q[1], 0.65f)
            vert(p[0], 0f, p[1], 0.65f)
            vert(q[0], h, q[1], 0.65f)
            vert(p[0], h, p[1], 0.65f)
        }

        vertexCount = data.size / 4
        buffer = ByteBuffer
            .allocateDirect(data.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
        for (f in data) buffer.put(f)
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
        scale: Float,
        r: Float,
        g: Float,
        b: Float,
        a: Float,
    ) {
        Matrix.setIdentityM(model, 0)
        Matrix.translateM(model, 0, x, y, z)
        Matrix.rotateM(model, 0, headingDeg, 0f, 1f, 0f)
        Matrix.scaleM(model, 0, scale, scale, scale)
        Matrix.multiplyMM(mvp, 0, viewProj, 0, model, 0)

        GLES20.glUseProgram(program)
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        GLES20.glEnable(GLES20.GL_DEPTH_TEST)
        GLES20.glDepthMask(true)

        GLES20.glUniformMatrix4fv(mvpUniform, 1, false, mvp, 0)
        GLES20.glUniform4f(colorUniform, r, g, b, a)

        buffer.rewind()
        buffer.position(0)
        GLES20.glEnableVertexAttribArray(positionAttrib)
        GLES20.glVertexAttribPointer(positionAttrib, 3, GLES20.GL_FLOAT, false, 4 * 4, buffer)
        buffer.position(3)
        GLES20.glEnableVertexAttribArray(shadeAttrib)
        GLES20.glVertexAttribPointer(shadeAttrib, 1, GLES20.GL_FLOAT, false, 4 * 4, buffer)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLES, 0, vertexCount)

        GLES20.glDisableVertexAttribArray(positionAttrib)
        GLES20.glDisableVertexAttribArray(shadeAttrib)
        GLES20.glDisable(GLES20.GL_DEPTH_TEST)
        GLES20.glDisable(GLES20.GL_BLEND)
    }

    companion object {
        private const val VERTEX_SHADER = """
            uniform mat4 u_ModelViewProjection;
            attribute vec4 a_Position;
            attribute float a_Shade;
            varying float v_Shade;
            void main() {
                v_Shade = a_Shade;
                gl_Position = u_ModelViewProjection * a_Position;
            }
        """

        private const val FRAGMENT_SHADER = """
            precision mediump float;
            uniform vec4 u_Color;
            varying float v_Shade;
            void main() {
                gl_FragColor = vec4(u_Color.rgb * v_Shade, u_Color.a);
            }
        """
    }
}
