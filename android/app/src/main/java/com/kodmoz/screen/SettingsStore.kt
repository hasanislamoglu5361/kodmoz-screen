package com.kodmoz.screen

import android.content.Context

class SettingsStore(context: Context) {
    private val prefs = context.applicationContext
        .getSharedPreferences("kodmoz_screen", Context.MODE_PRIVATE)

    var lastHost: String?
        get() = prefs.getString("last_host", null)
        set(value) = prefs.edit().putString("last_host", value).apply()

    var lastPort: Int
        get() = prefs.getInt("last_port", 9280)
        set(value) = prefs.edit().putInt("last_port", value).apply()

    var lastCode: String
        get() = prefs.getString("last_code", "") ?: ""
        set(value) = prefs.edit().putString("last_code", value).apply()

    var showStats: Boolean
        get() = prefs.getBoolean("show_stats", true)
        set(value) = prefs.edit().putBoolean("show_stats", value).apply()

    var keepAwake: Boolean
        get() = prefs.getBoolean("keep_awake", true)
        set(value) = prefs.edit().putBoolean("keep_awake", value).apply()

    fun codeFor(host: String): String? {
        return prefs.getString("code_$host", null)
    }

    fun saveCode(host: String, code: String) {
        prefs.edit().putString("code_$host", code).apply()
        lastCode = code
    }

    fun saveConnection(host: String, port: Int, code: String) {
        lastHost = host
        lastPort = port
        lastCode = code
        saveCode(host, code)
    }
}
