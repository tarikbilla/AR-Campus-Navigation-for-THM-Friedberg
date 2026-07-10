package net.godevs.thmcampusnav.ar.rendering

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.opengl.GLES20
import android.opengl.GLUtils
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.max

/**
 * Renders a line (or lines) of text as a camera-facing billboard quad in the AR
 * scene ("3D text"). The text is rasterised to a bitmap (with a rounded pill
 * background) and uploaded as a texture; the quad is oriented each frame using
 * the camera's right/up vectors so it always faces the viewer and scales with
 * distance like any other 3D object.
 *
 * Each instance owns one texture / one string.
 */
class BillboardTextRenderer {

    private var program = 0
    private var positionAttrib = 0
    private var texCoordAttrib = 0
    private var mvpUniform = 0
    private var texUniform = 0

    private var textureId = -1
    private var texWidth = 1
    private var texHeight = 1
    private var currentText: String? = null

    private lateinit var posBuffer: FloatBuffer
    private lateinit var uvBuffer: FloatBuffer

    fun createOnGlThread() {
        program = ShaderUtil.createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
        positionAttrib = GLES20.glGetAttribLocation(program, "a_Position")
        texCoordAttrib = GLES20.glGetAttribLocation(program, "a_TexCoord")
        mvpUniform = GLES20.glGetUniformLocation(program, "u_ModelViewProjection")
        texUniform = GLES20.glGetUniformLocation(program, "u_Texture")

        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        textureId = textures[0]

        posBuffer = ByteBuffer
            .allocateDirect(4 * 3 * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()

        // UVs for TL, TR, BL, BR (triangle strip); bitmap top row is t=0.
        uvBuffer = ByteBuffer
            .allocateDirect(4 * 2 * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
        uvBuffer.put(floatArrayOf(0f, 0f, 1f, 0f, 0f, 1f, 1f, 1f))
        uvBuffer.rewind()
    }

    /** Rasterises [text] (supports "\n") to the texture. No-op if unchanged. */
    fun setText(text: String) {
        if (text == currentText) return
        currentText = text
        upload(rasterize(text))
    }

    /**
     * Rasterises a professional info card — a small uppercase [title], a large
     * [big] value and a [sub] line — to the texture. No-op if unchanged.
     */
    fun setCard(title: String, big: String, sub: String) {
        val key = "CARD|$title|$big|$sub"
        if (key == currentText) return
        currentText = key
        upload(rasterizeCard(title, big, sub))
    }

    private fun upload(bmp: Bitmap) {
        texWidth = bmp.width
        texHeight = bmp.height
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)
        GLES20.glTexParameteri(
            GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(
            GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(
            GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(
            GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bmp, 0)
        bmp.recycle()
    }

    /**
     * Draws the label centred at world (cx,cy,cz), oriented to face the camera
     * using its [right] and [up] world axes, at [heightMeters] tall.
     */
    fun draw(
        cx: Float,
        cy: Float,
        cz: Float,
        right: FloatArray,
        up: FloatArray,
        viewProj: FloatArray,
        heightMeters: Float,
    ) {
        if (currentText == null) return
        val aspect = texWidth.toFloat() / texHeight.toFloat()
        val h = heightMeters
        val w = h * aspect
        val hw = w * 0.5f
        val hh = h * 0.5f

        // Corner = centre ± hw*right ± hh*up, ordered TL, TR, BL, BR.
        posBuffer.rewind()
        putCorner(cx, cy, cz, right, up, -hw, hh)
        putCorner(cx, cy, cz, right, up, hw, hh)
        putCorner(cx, cy, cz, right, up, -hw, -hh)
        putCorner(cx, cy, cz, right, up, hw, -hh)
        posBuffer.rewind()

        GLES20.glUseProgram(program)
        GLES20.glEnable(GLES20.GL_BLEND)
        // Android bitmaps are premultiplied.
        GLES20.glBlendFunc(GLES20.GL_ONE, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        GLES20.glDepthMask(false)

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)
        GLES20.glUniform1i(texUniform, 0)
        GLES20.glUniformMatrix4fv(mvpUniform, 1, false, viewProj, 0)

        GLES20.glEnableVertexAttribArray(positionAttrib)
        GLES20.glVertexAttribPointer(positionAttrib, 3, GLES20.GL_FLOAT, false, 0, posBuffer)
        uvBuffer.rewind()
        GLES20.glEnableVertexAttribArray(texCoordAttrib)
        GLES20.glVertexAttribPointer(texCoordAttrib, 2, GLES20.GL_FLOAT, false, 0, uvBuffer)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

        GLES20.glDisableVertexAttribArray(positionAttrib)
        GLES20.glDisableVertexAttribArray(texCoordAttrib)
        GLES20.glDepthMask(true)
        GLES20.glDisable(GLES20.GL_BLEND)
    }

    private fun putCorner(
        cx: Float, cy: Float, cz: Float,
        right: FloatArray, up: FloatArray, s: Float, t: Float,
    ) {
        posBuffer.put(cx + right[0] * s + up[0] * t)
        posBuffer.put(cy + right[1] * s + up[1] * t)
        posBuffer.put(cz + right[2] * s + up[2] * t)
    }

    /**
     * Draws the label lying **flat on the ground** (in the XZ plane at height
     * [y]), reading along the path direction ([dirX],[dirZ]) — like painted
     * text on a road. [alongMeters] is the label's length in the walking
     * direction; the across-path width follows the text's aspect ratio.
     */
    fun drawOnGround(
        cx: Float,
        y: Float,
        cz: Float,
        dirX: Float,
        dirZ: Float,
        viewProj: FloatArray,
        alongMeters: Float,
    ) {
        if (currentText == null) return
        var fx = dirX
        var fz = dirZ
        val flen = kotlin.math.sqrt(fx * fx + fz * fz)
        if (flen < 1e-4f) return
        fx /= flen; fz /= flen
        // Viewer's right when looking along the path = rotate forward -90° in XZ.
        val rx = fz
        val rz = -fx

        val aspect = texWidth.toFloat() / texHeight.toFloat()
        val halfLen = alongMeters * 0.5f            // forward extent
        val halfWid = alongMeters * aspect * 0.5f   // across-path extent

        // Ground quad corners in bitmap order TL, TR, BL, BR (top = far end).
        posBuffer.rewind()
        putGround(cx, y, cz, fx, fz, rx, rz, halfLen, -halfWid)  // TL far-left
        putGround(cx, y, cz, fx, fz, rx, rz, halfLen, halfWid)   // TR far-right
        putGround(cx, y, cz, fx, fz, rx, rz, -halfLen, -halfWid) // BL near-left
        putGround(cx, y, cz, fx, fz, rx, rz, -halfLen, halfWid)  // BR near-right
        posBuffer.rewind()

        GLES20.glUseProgram(program)
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_ONE, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        GLES20.glDepthMask(false)

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)
        GLES20.glUniform1i(texUniform, 0)
        GLES20.glUniformMatrix4fv(mvpUniform, 1, false, viewProj, 0)

        GLES20.glEnableVertexAttribArray(positionAttrib)
        GLES20.glVertexAttribPointer(positionAttrib, 3, GLES20.GL_FLOAT, false, 0, posBuffer)
        uvBuffer.rewind()
        GLES20.glEnableVertexAttribArray(texCoordAttrib)
        GLES20.glVertexAttribPointer(texCoordAttrib, 2, GLES20.GL_FLOAT, false, 0, uvBuffer)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

        GLES20.glDisableVertexAttribArray(positionAttrib)
        GLES20.glDisableVertexAttribArray(texCoordAttrib)
        GLES20.glDepthMask(true)
        GLES20.glDisable(GLES20.GL_BLEND)
    }

    private fun putGround(
        cx: Float, y: Float, cz: Float,
        fx: Float, fz: Float, rx: Float, rz: Float,
        along: Float, across: Float,
    ) {
        posBuffer.put(cx + fx * along + rx * across)
        posBuffer.put(y)
        posBuffer.put(cz + fz * along + rz * across)
    }

    private fun rasterize(text: String): Bitmap {
        val lines = text.split("\n")
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = 56f
            color = -0x1 // white
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        val fm = paint.fontMetrics
        val lineH = fm.descent - fm.ascent
        val padX = 40f
        val padY = 28f
        var maxW = 0f
        for (l in lines) maxW = max(maxW, paint.measureText(l))
        val w = (maxW + padX * 2).toInt().coerceAtLeast(1)
        val h = (lineH * lines.size + padY * 2).toInt().coerceAtLeast(1)

        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val radius = h * 0.30f
        val bg = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xCC0E1512.toInt() // dark, translucent
        }
        canvas.drawRoundRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), radius, radius, bg)
        val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 4f
            color = 0x66FFFFFF.toInt()
        }
        canvas.drawRoundRect(
            RectF(2f, 2f, w - 2f, h - 2f), radius, radius, border)

        var y = padY - fm.ascent
        for (l in lines) {
            canvas.drawText(l, padX, y, paint)
            y += lineH
        }
        return bmp
    }

    /** Rasterises a professional info card (title / big value / subtitle). */
    private fun rasterizeCard(title: String, big: String, sub: String): Bitmap {
        val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = 34f
            color = 0xFF7FE3AE.toInt() // brand light
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            letterSpacing = 0.10f
        }
        val bigPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = 84f
            color = -0x1 // white
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        val subPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = 34f
            color = 0xFFCFD8D3.toInt()
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
        }

        val titleFm = titlePaint.fontMetrics
        val bigFm = bigPaint.fontMetrics
        val subFm = subPaint.fontMetrics
        val titleH = titleFm.descent - titleFm.ascent
        val bigH = bigFm.descent - bigFm.ascent
        val subH = subFm.descent - subFm.ascent

        val padX = 46f
        val padTop = 34f
        val padBottom = 34f
        val gap1 = 8f
        val gap2 = 12f

        val contentW = max(
            titlePaint.measureText(title),
            max(bigPaint.measureText(big), subPaint.measureText(sub)),
        )
        val w = (contentW + padX * 2).toInt().coerceAtLeast(1)
        val h = (padTop + titleH + gap1 + bigH + gap2 + subH + padBottom)
            .toInt().coerceAtLeast(1)

        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val radius = 34f
        val cardPath = Path().apply {
            addRoundRect(
                RectF(0f, 0f, w.toFloat(), h.toFloat()), radius, radius,
                Path.Direction.CW,
            )
        }
        canvas.drawPath(cardPath, Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xF00E1512.toInt()
        })

        // Brand accent strip along the top edge.
        canvas.save()
        canvas.clipPath(cardPath)
        canvas.drawRect(0f, 0f, w.toFloat(), 8f, Paint().apply {
            color = 0xFF009640.toInt()
        })
        canvas.restore()

        canvas.drawRoundRect(
            RectF(2f, 2f, w - 2f, h - 2f), radius, radius,
            Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = 3f
                color = 0x33FFFFFF
            },
        )

        var top = padTop + 6f
        canvas.drawText(title.uppercase(), padX, top - titleFm.ascent, titlePaint)
        top += titleH + gap1
        canvas.drawText(big, padX, top - bigFm.ascent, bigPaint)
        top += bigH + gap2
        canvas.drawText(sub, padX, top - subFm.ascent, subPaint)

        return bmp
    }

    companion object {
        private const val VERTEX_SHADER = """
            uniform mat4 u_ModelViewProjection;
            attribute vec4 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            void main() {
                v_TexCoord = a_TexCoord;
                gl_Position = u_ModelViewProjection * a_Position;
            }
        """

        private const val FRAGMENT_SHADER = """
            precision mediump float;
            uniform sampler2D u_Texture;
            varying vec2 v_TexCoord;
            void main() {
                gl_FragColor = texture2D(u_Texture, v_TexCoord);
            }
        """
    }
}
