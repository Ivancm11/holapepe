package com.poodlehome;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.os.Bundle;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** "Más apps": every launchable app on the TV, alphabetically. Back returns home. */
public class AllAppsActivity extends Activity {

    /** System entries that show up as "apps" but are useless to open. */
    private static final Set<String> HIDDEN = new HashSet<>(Arrays.asList(
            "com.mstar.android.tv.disclaimercustomization"));

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        PackageManager pm = getPackageManager();

        ScrollView scroll = new ScrollView(this);
        scroll.setBackgroundColor(0xFF000000);
        LinearLayout list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        list.setPadding(Ui.dp(this, 44), Ui.dp(this, 30), Ui.dp(this, 44), Ui.dp(this, 30));
        scroll.addView(list);

        TextView title = new TextView(this);
        title.setText("Todas las apps");
        title.setTextSize(28);
        title.setTextColor(0xFFFFFFFF);
        title.setPadding(Ui.dp(this, 12), 0, 0, Ui.dp(this, 14));
        list.addView(title);

        Map<String, CharSequence> apps = new LinkedHashMap<>();
        for (String category : new String[] {Intent.CATEGORY_LEANBACK_LAUNCHER, Intent.CATEGORY_LAUNCHER}) {
            Intent q = new Intent(Intent.ACTION_MAIN).addCategory(category);
            for (ResolveInfo ri : pm.queryIntentActivities(q, 0)) {
                String pkg = ri.activityInfo.packageName;
                if (pkg.equals(getPackageName()) || HIDDEN.contains(pkg) || apps.containsKey(pkg)) continue;
                apps.put(pkg, ri.loadLabel(pm));
            }
        }
        List<Map.Entry<String, CharSequence>> sorted = new ArrayList<>(apps.entrySet());
        sorted.sort((a, b) -> a.getValue().toString().compareToIgnoreCase(b.getValue().toString()));

        for (Map.Entry<String, CharSequence> e : sorted) {
            String pkg = e.getKey();
            LinearLayout row = Ui.row(this, Ui.icon(pm, pkg), e.getValue(), 17, 0xFFFFFFFF, v -> {
                Ui.launch(this, pkg);
                finish();
            });
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(Ui.dp(this, 360), -2);
            list.addView(row, lp);
        }

        setContentView(scroll);
        if (list.getChildCount() > 1) list.getChildAt(1).requestFocus();
    }
}
