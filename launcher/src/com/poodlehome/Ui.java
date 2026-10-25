package com.poodlehome;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.view.View;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

/** Shared row styling and app launching for both screens. */
final class Ui {
    static final String PREFS = "home";
    static final String PREF_LAST = "last";

    private static final int WHITE = 0xFFFFFFFF;
    private static final int FOCUS_BG = 0xF2FFFFFF;
    private static final int FOCUS_TEXT = 0xFF000000;

    private Ui() {}

    static int dp(Context c, float v) {
        return Math.round(v * c.getResources().getDisplayMetrics().density);
    }

    /** A focusable list row: optional icon + label, white pill when focused. */
    static LinearLayout row(Context c, Drawable icon, CharSequence label, float textSp, int textColor,
                            View.OnClickListener click) {
        LinearLayout row = new LinearLayout(c);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(dp(c, 12), dp(c, 6), dp(c, 12), dp(c, 6));
        row.setFocusable(true);
        row.setClickable(true);
        row.setOnClickListener(click);

        if (icon != null) {
            ImageView iv = new ImageView(c);
            iv.setImageDrawable(icon);
            iv.setScaleType(ImageView.ScaleType.FIT_CENTER);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(c, 26), dp(c, 26));
            lp.rightMargin = dp(c, 12);
            row.addView(iv, lp);
        }

        TextView tv = new TextView(c);
        tv.setText(label);
        tv.setTextSize(textSp);
        tv.setTextColor(textColor);
        tv.setSingleLine(true);
        row.addView(tv);

        styleFocus(row, tv, textColor);
        return row;
    }

    /** A small focusable text button for the shortcuts row. */
    static TextView chip(Context c, CharSequence label, View.OnClickListener click) {
        TextView tv = new TextView(c);
        tv.setText(label);
        tv.setTextSize(13);
        int color = 0xB3FFFFFF;
        tv.setTextColor(color);
        tv.setPadding(dp(c, 10), dp(c, 5), dp(c, 10), dp(c, 5));
        tv.setFocusable(true);
        tv.setClickable(true);
        tv.setOnClickListener(click);
        styleFocus(tv, tv, color);
        return tv;
    }

    private static void styleFocus(View target, TextView text, int idleTextColor) {
        GradientDrawable bg = new GradientDrawable();
        bg.setCornerRadius(dp(target.getContext(), 8));
        bg.setColor(0);
        target.setBackground(bg);
        target.setOnFocusChangeListener((v, focused) -> {
            bg.setColor(focused ? FOCUS_BG : 0);
            text.setTextColor(focused ? FOCUS_TEXT : idleTextColor);
            text.setTypeface(null, focused ? Typeface.BOLD : Typeface.NORMAL);
            float s = focused ? 1.04f : 1f;
            v.animate().scaleX(s).scaleY(s).setDuration(90).start();
        });
        target.setPivotX(0);
    }

    static Intent launchIntent(PackageManager pm, String pkg) {
        Intent i = pm.getLeanbackLaunchIntentForPackage(pkg);
        if (i == null) i = pm.getLaunchIntentForPackage(pkg);
        return i;
    }

    static Drawable icon(PackageManager pm, String pkg) {
        try {
            return pm.getApplicationIcon(pkg);
        } catch (PackageManager.NameNotFoundException e) {
            return null;
        }
    }

    static CharSequence label(PackageManager pm, String pkg) {
        try {
            return pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0));
        } catch (PackageManager.NameNotFoundException e) {
            return pkg;
        }
    }

    /** Opens an app and remembers it so the home screen focuses it next time. */
    static void launch(Activity a, String pkg) {
        Intent i = launchIntent(a.getPackageManager(), pkg);
        if (i == null) {
            Toast.makeText(a, "No se puede abrir " + pkg, Toast.LENGTH_SHORT).show();
            return;
        }
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            a.startActivity(i);
            a.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(PREF_LAST, pkg).apply();
        } catch (ActivityNotFoundException | SecurityException e) {
            Toast.makeText(a, "No se puede abrir " + pkg, Toast.LENGTH_SHORT).show();
        }
    }

    static void start(Activity a, Intent i) {
        try {
            a.startActivity(i);
        } catch (ActivityNotFoundException | SecurityException e) {
            Toast.makeText(a, "No disponible en esta TV", Toast.LENGTH_SHORT).show();
        }
    }
}
