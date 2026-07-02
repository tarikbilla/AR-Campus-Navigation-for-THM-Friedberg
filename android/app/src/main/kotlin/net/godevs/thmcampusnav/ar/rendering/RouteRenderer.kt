package net.godevs.thmcampusnav.ar.rendering

import android.opengl.GLES20
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.sqrt

/**
 * Renders the walking route as a ground-hugging ribbon (a triangle strip) with
 * an animated "flow" that runs toward the destination, giving a clear
 * follow-the-path cue anchored on the real ground in the camera view.
 *
 * Input points are already in ARCore **world** space (metres), so the model
 * matrix is identity and only the view-projection matrix is supplied.
 */
class RouteRenderer {

    private var program = 0
    private var positionAttrib = 0
    private var distAttrib = 0
    private var mvpUniform = 0
    private var phaseUniform = 0
    private var colorAUniform = 0
    private var colorBUniform = 0

    private val halfWidth = 0.55f // ribbon half-width in metres

    // Reused across frames to avoid per-frame direct-buffer allocation (GC churn).
    private var posBuf: FloatBuffer? = null
    private var distBuf: FloatBuffer? = null
    private var capacityVerts = 0

    private fun ensureCapacity(stripVerts: Int) {
        if (posBuf != null && capacityVerts >= stripVerts) {
            posBuf!!.clear()
            distBuf!!.clear()
            return
        }
        capacityVerts = stripVerts
        posBuf = ByteBuffer
            .allocateDirect(stripVerts * 3 * FLOAT_SIZE)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
        distBuf = ByteBuffer
            .allocateDirect(stripVerts * FLOAT_SIZE)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
    }

    fun createOnGlThread() {
        program = ShaderUtil.createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
        positionAttrib = GLES20.glGetAttribLocation(program, "a_Position")
        distAttrib = GLES20.glGetAttribLocation(program, "a_Dist")
        mvpUniform = GLES20.glGetUniformLocation(program, "u_ModelViewProjection")
        phaseUniform = GLES20.glGetUniformLocation(program, "u_Phase")
        colorAUniform = GLES20.glGetUniformLocation(program, "u_ColorA")
        colorBUniform = GLES20.glGetUniformLocation(program, "u_ColorB")
    }

    /**
     * @param worldPoints flat [x,y,z] array of route centre points in world space
     * @param count number of points (worldPoints.size / 3)
     * @param viewProj combined view * projection matrix
     * @param phase animation phase (increasing over time)
     */
    fun draw(worldPoints: FloatArray, count: Int, viewProj: FloatArray, phase: Float) {
        if (count < 2) return

        val stripVerts = count * 2
        ensureCapacity(stripVerts)
        val posBuf = this.posBuf!!
        val distBuf = this.distBuf!!

        var cumDist = 0f
        for (i in 0 until count) {
            val cx = worldPoints[i * 3]
            val cy = worldPoints[i * 3 + 1]
            val cz = worldPoints[i * 3 + 2]

            if (i > 0) {
                val dx = cx - worldPoints[(i - 1) * 3]
                val dz = cz - worldPoints[(i - 1) * 3 + 2]
                cumDist += sqrt(dx * dx + dz * dz)
            }

            // Horizontal direction at this point (average of neighbouring segments).
            var dirX = 0f
            var dirZ = 0f
            if (i > 0) {
                dirX += cx - worldPoints[(i - 1) * 3]
                dirZ += cz - worldPoints[(i - 1) * 3 + 2]
            }
            if (i < count - 1) {
                dirX += worldPoints[(i + 1) * 3] - cx
                dirZ += worldPoints[(i + 1) * 3 + 2] - cz
            }
            val dlen = sqrt(dirX * dirX + dirZ * dirZ)
            if (dlen > 1e-4f) {
                dirX /= dlen
                dirZ /= dlen
            }
            // Left/right perpendicular in the horizontal plane: (dz, 0, -dx).
            val perpX = dirZ * halfWidth
            val perpZ = -dirX * halfWidth

            posBuf.put(cx + perpX); posBuf.put(cy); posBuf.put(cz + perpZ)
            distBuf.put(cumDist)
            posBuf.put(cx - perpX); posBuf.put(cy); posBuf.put(cz - perpZ)
            distBuf.put(cumDist)
        }
        posBuf.rewind()
        distBuf.rewind()

        GLES20.glUseProgram(program)
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        GLES20.glDepthMask(false)

        GLES20.glUniformMatrix4fv(mvpUniform, 1, false, viewProj, 0)
        GLES20.glUniform1f(phaseUniform, phase)
        GLES20.glUniform4f(colorAUniform, 0.0f, 0.60f, 0.35f, 0.55f)   // THM green
        GLES20.glUniform4f(colorBUniform, 0.10f, 0.75f, 1.0f, 0.85f)   // bright accent

        GLES20.glEnableVertexAttribArray(positionAttrib)
        GLES20.glVertexAttribPointer(positionAttrib, 3, GLES20.GL_FLOAT, false, 0, posBuf)
        GLES20.glEnableVertexAttribArray(distAttrib)
        GLES20.glVertexAttribPointer(distAttrib, 1, GLES20.GL_FLOAT, false, 0, distBuf)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, stripVerts)

        GLES20.glDisableVertexAttribArray(positionAttrib)
        GLES20.glDisableVertexAttribArray(distAttrib)
        GLES20.glDepthMask(true)
        GLES20.glDisable(GLES20.GL_BLEND)
    }

    companion object {
        private const val FLOAT_SIZE = 4

        private const val VERTEX_SHADER = """
            uniform mat4 u_ModelViewProjection;
            attribute vec4 a_Position;
            attribute float a_Dist;
            varying float v_Dist;
            void main() {
                v_Dist = a_Dist;
                gl_Position = u_ModelViewProjection * a_Position;
            }
        """

        // Moving bands flow toward the destination; colour shifts green -> accent.
        private const val FRAGMENT_SHADER = """
            precision mediump float;
            uniform vec4 u_ColorA;
            uniform vec4 u_ColorB;
            uniform float u_Phase;
            varying float v_Dist;
            void main() {
                float f = fract(v_Dist * 0.6 - u_Phase);
                float pulse = 1.0 - abs(2.0 * f - 1.0);
                vec3 col = mix(u_ColorA.rgb, u_ColorB.rgb, pulse);
                float a = mix(u_ColorA.a, u_ColorB.a, pulse);
                gl_FragColor = vec4(col, a);
            }
        """
    }
}
