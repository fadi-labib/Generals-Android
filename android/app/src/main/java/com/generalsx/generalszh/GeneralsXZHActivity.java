package com.generalsx.generalszh;

import org.libsdl.app.SDLActivity;

/**
 * GeneralsX @feature FadiLabib 06/07/2026 Thin SDLActivity shell.
 * getArguments() forwards an intent string extra "args" as engine argv,
 * enabling headless runs: adb shell am start -n <pkg>/.GeneralsXZHActivity
 *   --es args "-headless -replay 00000000.rep"
 */
public class GeneralsXZHActivity extends SDLActivity {
    @Override
    protected String[] getLibraries() {
        return new String[] { "SDL3", "main" };
    }

    @Override
    protected String[] getArguments() {
        String args = getIntent() != null ? getIntent().getStringExtra("args") : null;
        if (args == null || args.trim().isEmpty()) {
            return new String[0];
        }
        return args.trim().split("\\s+");
    }
}
