package com.poodlehome;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Typeface;
import android.media.tv.TvContract;
import android.media.tv.TvInputInfo;
import android.media.tv.TvInputManager;
import android.os.Bundle;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextClock;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Calendar;
import java.util.List;

/**
 * The home screen: clock, a short list of favourite apps, "Más apps", a shortcuts row,
 * and a wallpaper photo. Nothing runs in the background and nothing touches the network.
 *
 * Config lives in the app's own folder on the TV (written by mitv.ps1 over adb):
 *   /sdcard/Android/data/com.poodlehome/files/apps.txt        one package per line, in order
 *   /sdcard/Android/data/com.poodlehome/files/wallpapers/*    photos; one per day, in name order
 */
public class HomeActivity extends Activity {

    static final List<String> DEFAULT_FAVORITES = Arrays.asList(
            "com.netflix.ninja",
            "tv.twitch.android.app",
            "com.apple.atve.androidtv.appletv",
            "com.spotify.tv.android",
            "com.amazon.amazonvideo.livingroom",
            "com.wbd.stream",
            "com.disney.disneyplus");

    private static final String MI_TV_PLUS = "com.mitv.tvhome.mitvplus";

    private ImageView wallpaper;
    private LinearLayout favorites;
    private LinearLayout shortcuts;
    private View moreApps;
    private String shownWallpaperKey;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(buildLayout());
    }

    @Override
    protected void onResume() {
        super.onResume();
        // Rebuilt on every return: cheap (a handful of rows) and picks up config/app changes.
        showWallpaper();
        buildFavorites();
        buildShortcuts();
        focusLastApp();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        focusLastApp();
    }

    @Override
    public void onBackPressed() {
        // Home has nowhere to go back to.
    }

    private View buildLayout() {
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(0xFF000000);

        wallpaper = new ImageView(this);
        wallpaper.setScaleType(ImageView.ScaleType.CENTER_CROP);
        root.addView(wallpaper, new FrameLayout.LayoutParams(-1, -1));

        LinearLayout column = new LinearLayout(this);
        column.setOrientation(LinearLayout.VERTICAL);
        FrameLayout.LayoutParams colLp = new FrameLayout.LayoutParams(Ui.dp(this, 320), -2);
        colLp.leftMargin = Ui.dp(this, 44);
        colLp.topMargin = Ui.dp(this, 34);
        root.addView(column, colLp);

        TextClock time = new TextClock(this);
        time.setFormat24Hour("HH:mm");
        time.setFormat12Hour("HH:mm");
        time.setTextSize(56);
        time.setTextColor(0xFFFFFFFF);
        time.setTypeface(Typeface.create("sans-serif-light", Typeface.NORMAL));
        column.addView(time);

        TextClock date = new TextClock(this);
        date.setFormat24Hour("EEEE, d 'de' MMMM");
        date.setFormat12Hour("EEEE, d 'de' MMMM");
        date.setTextSize(15);
        date.setTextColor(0xB3FFFFFF);
        date.setPadding(Ui.dp(this, 3), 0, 0, Ui.dp(this, 14));
        column.addView(date);

        favorites = new LinearLayout(this);
        favorites.setOrientation(LinearLayout.VERTICAL);
        column.addView(favorites);

        moreApps = Ui.row(this, null, "▸  Más apps", 15, 0x99FFFFFF,
                v -> startActivity(new Intent(this, AllAppsActivity.class)));
        moreApps.setId(View.generateViewId());
        column.addView(moreApps);

        shortcuts = new LinearLayout(this);
        shortcuts.setOrientation(LinearLayout.HORIZONTAL);
        FrameLayout.LayoutParams scLp = new FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM | Gravity.START);
        scLp.leftMargin = Ui.dp(this, 38);
        scLp.bottomMargin = Ui.dp(this, 22);
        root.addView(shortcuts, scLp);

        return root;
    }

    private void buildFavorites() {
        PackageManager pm = getPackageManager();
        favorites.removeAllViews();
        for (String pkg : readFavorites()) {
            if (Ui.launchIntent(pm, pkg) == null) continue;   // not installed or disabled
            View row = Ui.row(this, Ui.icon(pm, pkg), Ui.label(pm, pkg), 18, 0xFFFFFFFF,
                    v -> Ui.launch(this, pkg));
            row.setTag(pkg);
            favorites.addView(row);
        }
    }

    private void buildShortcuts() {
        shortcuts.removeAllViews();
        shortcuts.addView(Ui.chip(this, "Ajustes", v -> Ui.start(this, new Intent(Settings.ACTION_SETTINGS))));
        shortcuts.addView(Ui.chip(this, "HDMI", v -> pickInput()));
        if (Ui.launchIntent(getPackageManager(), MI_TV_PLUS) != null) {
            shortcuts.addView(Ui.chip(this, "Mi TV+", v -> Ui.launch(this, MI_TV_PLUS)));
        }
        // Down from "Más apps" lands on the first shortcut, not whichever chip is geometrically closest.
        View first = shortcuts.getChildAt(0);
        first.setId(View.generateViewId());
        moreApps.setNextFocusDownId(first.getId());
        for (int i = 0; i < shortcuts.getChildCount(); i++) shortcuts.getChildAt(i).setNextFocusUpId(moreApps.getId());
    }

    private void focusLastApp() {
        if (favorites.getChildCount() == 0) return;
        String last = getSharedPreferences(Ui.PREFS, Context.MODE_PRIVATE).getString(Ui.PREF_LAST, null);
        View target = last == null ? null : favorites.findViewWithTag(last);
        (target != null ? target : favorites.getChildAt(0)).requestFocus();
    }

    private List<String> readFavorites() {
        File f = new File(getExternalFilesDir(null), "apps.txt");
        if (!f.isFile()) return DEFAULT_FAVORITES;
        List<String> out = new ArrayList<>();
        try (BufferedReader r = new BufferedReader(new FileReader(f))) {
            String line;
            while ((line = r.readLine()) != null) {
                line = line.trim();
                if (!line.isEmpty() && !line.startsWith("#")) out.add(line);
            }
        } catch (IOException e) {
            return DEFAULT_FAVORITES;
        }
        return out.isEmpty() ? DEFAULT_FAVORITES : out;
    }

    /** Shows today's photo; only decodes again when the chosen file changes. */
    private void showWallpaper() {
        File dir = getExternalFilesDir("wallpapers");
        File[] files = dir == null ? null : dir.listFiles((d, name) -> {
            String n = name.toLowerCase();
            return n.endsWith(".png") || n.endsWith(".jpg") || n.endsWith(".jpeg") || n.endsWith(".webp");
        });
        if (files == null || files.length == 0) {
            wallpaper.setImageDrawable(null);
            shownWallpaperKey = null;
            return;
        }
        Arrays.sort(files);
        File pick = files[Calendar.getInstance().get(Calendar.DAY_OF_YEAR) % files.length];
        String key = pick.getPath() + ":" + pick.lastModified();
        if (key.equals(shownWallpaperKey)) return;

        BitmapFactory.Options bounds = new BitmapFactory.Options();
        bounds.inJustDecodeBounds = true;
        BitmapFactory.decodeFile(pick.getPath(), bounds);
        BitmapFactory.Options opts = new BitmapFactory.Options();
        opts.inSampleSize = 1;
        while (bounds.outWidth / (opts.inSampleSize * 2) >= 1920) opts.inSampleSize *= 2;
        opts.inPreferredConfig = Bitmap.Config.RGB_565;   // half the memory, no visible difference on a photo
        Bitmap bmp = BitmapFactory.decodeFile(pick.getPath(), opts);
        if (bmp != null) {
            wallpaper.setImageBitmap(bmp);
            shownWallpaperKey = key;
        }
    }

    /** Lists the TV's HDMI/AV inputs and switches to the one picked. */
    private void pickInput() {
        List<TvInputInfo> inputs = new ArrayList<>();
        try {
            TvInputManager tim = (TvInputManager) getSystemService(Context.TV_INPUT_SERVICE);
            for (TvInputInfo info : tim.getTvInputList()) {
                if (info.isPassthroughInput() && !info.isHidden(this)) inputs.add(info);
            }
        } catch (RuntimeException ignored) {
            // Fall through to the empty case.
        }
        if (inputs.isEmpty()) {
            Ui.start(this, new Intent(Settings.ACTION_SETTINGS));
            return;
        }
        inputs.sort((a, b) -> inputLabel(a).toString().compareToIgnoreCase(inputLabel(b).toString()));
        CharSequence[] labels = new CharSequence[inputs.size()];
        for (int i = 0; i < labels.length; i++) labels[i] = inputLabel(inputs.get(i));
        new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                .setTitle("Entrada")
                .setItems(labels, (d, which) -> Ui.start(this, new Intent(Intent.ACTION_VIEW,
                        TvContract.buildChannelUriForPassthroughInput(inputs.get(which).getId()))))
                .show();
    }

    private CharSequence inputLabel(TvInputInfo info) {
        CharSequence custom = info.loadCustomLabel(this);
        return custom != null ? custom : info.loadLabel(this);
    }
}
