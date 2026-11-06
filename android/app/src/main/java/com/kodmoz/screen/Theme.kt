package com.kodmoz.screen

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

val KodmozPurple = Color(0xFF8E8BFF)
val KodmozTeal = Color(0xFF62D6E8)
val KodmozBackground = Color(0xFF0B0D16)
val KodmozSurface = Color(0xFF151827)
val KodmozSurfaceHigh = Color(0xFF1D2135)
val KodmozOutline = Color(0xFF3B4160)
val KodmozText = Color(0xFFECEEF9)
val KodmozTextDim = Color(0xFFAEB4CB)

private val Colors = darkColorScheme(
    primary = KodmozPurple,
    onPrimary = Color(0xFF11110F),
    primaryContainer = Color(0xFF2E2A6E),
    onPrimaryContainer = Color(0xFFE4E2FF),
    secondary = KodmozTeal,
    onSecondary = Color(0xFF04252B),
    secondaryContainer = Color(0xFF123A42),
    onSecondaryContainer = Color(0xFFB8F0F8),
    background = KodmozBackground,
    onBackground = KodmozText,
    surface = KodmozSurface,
    onSurface = KodmozText,
    surfaceVariant = KodmozSurfaceHigh,
    onSurfaceVariant = KodmozTextDim,
    outline = KodmozOutline,
    outlineVariant = Color(0xFF282D45),
    error = Color(0xFFFFB4AB),
)

private val KodmozTypography = Typography(
    displaySmall = TextStyle(
        fontSize = 34.sp,
        lineHeight = 40.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = (-0.8).sp,
    ),
    headlineMedium = TextStyle(
        fontSize = 26.sp,
        lineHeight = 32.sp,
        fontWeight = FontWeight.SemiBold,
        letterSpacing = (-0.4).sp,
    ),
    titleLarge = TextStyle(
        fontSize = 20.sp,
        lineHeight = 26.sp,
        fontWeight = FontWeight.SemiBold,
    ),
    titleMedium = TextStyle(
        fontSize = 16.sp,
        lineHeight = 22.sp,
        fontWeight = FontWeight.SemiBold,
    ),
    bodyLarge = TextStyle(fontSize = 15.sp, lineHeight = 21.sp),
    bodyMedium = TextStyle(fontSize = 13.sp, lineHeight = 18.sp),
    labelLarge = TextStyle(
        fontSize = 14.sp,
        fontWeight = FontWeight.SemiBold,
        letterSpacing = 0.2.sp,
    ),
)

@Composable
fun KodmozTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = Colors,
        typography = KodmozTypography,
        content = content,
    )
}
