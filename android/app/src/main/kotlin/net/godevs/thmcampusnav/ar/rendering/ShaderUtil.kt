package net.godevs.thmcampusnav.ar.rendering

import android.opengl.GLES20
import android.util.Log

/** Small helpers for compiling GLSL shaders and checking for GL errors. */
object ShaderUtil {
    private const val TAG = "ShaderUtil"

    /** Compiles a shader of [type] from inline [source] and returns its handle. */
    fun loadGLShader(type: Int, source: String): Int {
        var shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, source)
        GLES20.glCompileShader(shader)

        val compiled = IntArray(1)
        GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, compiled, 0)
        if (compiled[0] == 0) {
            Log.e(TAG, "Error compiling shader: ${GLES20.glGetShaderInfoLog(shader)}")
            GLES20.glDeleteShader(shader)
            shader = 0
        }
        require(shader != 0) { "Error creating shader." }
        return shader
    }

    /** Links a vertex + fragment shader pair into a program and returns its handle. */
    fun createProgram(vertexSource: String, fragmentSource: String): Int {
        val vertexShader = loadGLShader(GLES20.GL_VERTEX_SHADER, vertexSource)
        val fragmentShader = loadGLShader(GLES20.GL_FRAGMENT_SHADER, fragmentSource)
        val program = GLES20.glCreateProgram()
        GLES20.glAttachShader(program, vertexShader)
        GLES20.glAttachShader(program, fragmentShader)
        GLES20.glLinkProgram(program)

        val linkStatus = IntArray(1)
        GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, linkStatus, 0)
        require(linkStatus[0] == GLES20.GL_TRUE) {
            "Error linking program: ${GLES20.glGetProgramInfoLog(program)}"
        }
        return program
    }

    /** Logs any pending GL error for [label]; call after GL operations while debugging. */
    fun checkGLError(label: String) {
        var error: Int
        while (GLES20.glGetError().also { error = it } != GLES20.GL_NO_ERROR) {
            Log.e(TAG, "$label: glError $error")
        }
    }
}
