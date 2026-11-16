{ pkgs, config, inputs, ... }:

let
  androidSdk = inputs.android-nixpkgs.sdk.${pkgs.system} (sdkPkgs: with sdkPkgs; [
    # This command-line tools release runs on the project's Java 17.
    cmdline-tools-13-0
    platform-tools
    platforms-android-35
    build-tools-35-0-0
  ]);
  androidHome = "${androidSdk}/share/android-sdk";
in
{
  packages = [ androidSdk ];

  languages.java = {
    enable = true;
    jdk.package = pkgs.jdk17;
    lsp.enable = false;
  };

  env = {
    ANDROID_HOME = androidHome;
    ANDROID_SDK_ROOT = androidHome;
    GRADLE_USER_HOME = "${config.devenv.state}/gradle";
    # Use the SDK's Nix-patched executable rather than Maven's host binary.
    GRADLE_OPTS = "-Dorg.gradle.project.android.aapt2FromMavenOverride=${androidHome}/build-tools/35.0.0/aapt2";
  };

  # Entering the shell does not build, install or overwrite local configuration.
  enterShell = ''
    export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/13.0/bin:$ANDROID_HOME/build-tools/35.0.0:$PATH"
  '';

  enterTest = ''
    set -euo pipefail
    java -version
    test "$(java -XshowSettings:properties -version 2>&1 | awk '/java.specification.version =/ { print $3 }')" = 17
    test "$JAVA_HOME/bin/java" -ef "$(command -v java)"
    adb version
    sdkmanager --version
    aapt2 version
    test -f "$ANDROID_HOME/platforms/android-35/android.jar"
    test -x "$ANDROID_HOME/build-tools/35.0.0/aapt2"
    test "$ANDROID_HOME" = "$ANDROID_SDK_ROOT"
    test -x ./gradlew
  '';
}
