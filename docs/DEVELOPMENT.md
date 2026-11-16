# Desarrollo local con devenv

Esta guía describe el entorno para Linux y la variante `GitHubDebug`. Nix y devenv deben estar instalados. Los comandos se ejecutan desde la raíz del repositorio. El 16 de noviembre de 2026 se verificaron el entorno, la resolución de dependencias, la compilación del APK debug y la prueba unitaria disponible. No se instaló ni abrió la aplicación en un dispositivo.

## Entorno reproducible

La configuración está en `devenv.nix` y `devenv.yaml`, con revisiones fijadas en `devenv.lock`. Utiliza `android-nixpkgs` y proporciona:

- JDK 17.
- Android SDK Platform 35, build-tools `35.0.0`, platform-tools y cmdline-tools `13.0`.
- `JAVA_HOME` y las herramientas Java del JDK configurado.
- `ANDROID_HOME` y `ANDROID_SDK_ROOT` apuntando al SDK de Nix.
- `GRADLE_USER_HOME = "${config.devenv.state}/gradle"`. En la disposición habitual corresponde a `.devenv/state/gradle`, pero la fuente de verdad es el valor real de `config.devenv.state`, no una ruta absoluta asumida. Dentro de la shell se puede consultar con `printf '%s\n' "$GRADLE_USER_HOME"`.
- `GRADLE_OPTS` con `-Dorg.gradle.project.android.aapt2FromMavenOverride=.../build-tools/35.0.0/aapt2`, usando la ruta real del SDK. Así Gradle utiliza el AAPT2 adaptado a Nix en lugar del binario de Maven. No eliminar ni sobrescribir este ajuste al compilar.

Entrar al entorno:

```sh
devenv shell
```

La shell prepara variables y `PATH`. **No instala la aplicación, no la compila y no escribe `local.properties`**. Nix puede obtener o materializar las dependencias del entorno al entrar. No hace falta crear `local.properties` para este flujo, pues el SDK se comunica mediante las variables del entorno.

No usar `sdkmanager` para instalar, actualizar o eliminar componentes del SDK en el Nix store. El SDK es gestionado por Nix. Cualquier cambio de componentes debe hacerse de forma declarativa en la configuración, no mutando su ruta. La comprobación `sdkmanager --version` no instala componentes.

## Comprobación del entorno

Desde la raíz del proyecto:

```sh
devenv test
```

El `enterTest` actual comprueba Java 17 y su correspondencia con `JAVA_HOME`, las versiones de `adb`, `sdkmanager` y `aapt2`, la presencia de `android-35/android.jar`, el ejecutable AAPT2, la igualdad de las variables del SDK y que `./gradlew` sea ejecutable. **No compila la aplicación ni ejecuta pruebas unitarias o de IA**.

## Preparación explícita y compilación debug

Dentro de `devenv shell`, preparar el archivo que `app/build.gradle.kts` aplica incondicionalmente:

```sh
cp -n secret.gradle.kts.example secret.gradle.kts
```

`cp -n` no sobrescribe un `secret.gradle.kts` existente. Este paso es manual, no un efecto de entrar en la shell. La plantilla contiene la estructura de configuración esperada con valores de firma vacíos. Para `GitHubDebug` no se necesitan los secretos de firma release ni `key.jks`, aunque se configure la variante release en el script. No introducir credenciales release para este flujo ni publicarlas en el repositorio.

Comprobar el wrapper y después solicitar compilación y pruebas locales:

```sh
./gradlew --version
./gradlew --no-daemon --max-workers=2 :app:assembleGitHubDebug :app:testGitHubDebugUnitTest
```

El wrapper declara Gradle `8.13`. Su primera ejecución puede descargar la distribución y las dependencias necesarias. Revisar que la JVM mostrada sea Java 17. Los límites de daemon y workers se aplican explícitamente a la compilación y las pruebas anteriores.

La resolución de dependencias también puede inspeccionarse explícitamente:

```sh
./gradlew --no-daemon --max-workers=2 :app:dependencies --configuration GitHubDebugRuntimeClasspath
```

El informe verificado no contiene dependencias `FAILED`, incluidas `io.github.skyd666:settings:1.0-beta03`, `io.github.skyd666:compone:1.0-beta05` y ObjectBox `4.0.3`. Gradle descarga estas librerías, no hay módulos internos adicionales que instalar.

### APK generado

La compilación verificada generó el APK universal:

```text
app/build/outputs/apk/GitHub/debug/Rays_2.4-alpha04_universal_debug_GitHub.apk
```

La ruta respeta el flavor `GitHub` y el tipo `debug`. El nombre se deriva de `app/build.gradle.kts`: `versionName = "2.4-alpha04"` y patrón `Rays_${versionName}_${abi}_${buildType.name}_${flavorName}.apk`, con `universal` cuando no hay filtro ABI. También se configuran APK por `arm64-v8a`, `armeabi-v7a`, `x86` y `x86_64`. Si cambia la versión o la lógica de salidas, revisar el nombre, no asumir que este archivo ya existe.

### Instalación posterior, a cargo del usuario

La aplicación debug tiene identificador **`com.skyd.rays.debug`**, por `applicationId = "com.skyd.rays"` más el sufijo `.debug`. Requiere **Android 7.0 o superior, API 24 como mínimo** (`minSdk = 24`).

Cuando el usuario quiera instalarla, con un dispositivo o emulador compatible conectado y autorizado para ADB, podrá ejecutar dentro del entorno:

```sh
./gradlew --no-daemon --max-workers=2 :app:installGitHubDebug
```

Este comando sí solicita instalar la aplicación y puede compilar lo necesario. No se ejecuta como parte de esta guía ni de la validación documental.

## Modelos de IA ausentes

En este checkout no hay archivos `.tflite` bajo `app/src`. Las siguientes rutas de assets se derivan de las cargas explícitas en el código, no de nombres supuestos:

| Archivo esperado | Código que lo carga | Impacto de su ausencia |
| --- | --- | --- |
| `app/src/main/assets/stickerclassification/sticker_classification.tflite` | `app/src/main/java/com/skyd/rays/model/respository/AddRepository.kt`, `setAssetFilePath` | La clasificación predeterminada de stickers y sus recomendaciones de etiquetas no disponen del modelo requerido. El código permite seleccionar un modelo externo, pero eso no aporta el asset predeterminado. |
| `app/src/main/assets/mobilenet_v3_small.tflite` | `app/src/main/java/com/skyd/rays/model/respository/ImageSearchRepository.kt`, `setModelAssetPath` | No puede inicializarse el modelo de embeddings necesario para buscar imágenes similares. |
| `app/src/main/assets/predict_int8.tflite` | `app/src/main/java/com/skyd/rays/util/StyleTransferUtil.kt`, `FileUtil.loadMappedFile` | Falta el predictor de la modalidad INT8 de transferencia de estilo, seleccionada por defecto. |
| `app/src/main/assets/transfer_int8.tflite` | `app/src/main/java/com/skyd/rays/util/StyleTransferUtil.kt`, `FileUtil.loadMappedFile` | Falta el transformador de la modalidad INT8. |
| `app/src/main/assets/predict_float16.tflite` | `app/src/main/java/com/skyd/rays/util/StyleTransferUtil.kt`, `FileUtil.loadMappedFile` | Falta el predictor de la modalidad alternativa FLOAT16. |
| `app/src/main/assets/transfer_float16.tflite` | `app/src/main/java/com/skyd/rays/util/StyleTransferUtil.kt`, `FileUtil.loadMappedFile` | Falta el transformador de la modalidad alternativa FLOAT16. |

`StyleTransferUtil` carga una pareja predictor/transformador según la modalidad y lanza un error si no puede inicializar los modelos. No se debe interpretar una compilación correcta como prueba de que estas funciones operan en ejecución.

El asset `app/src/main/assets/stickerclassification/lang/en.txt` sí está presente. `AddRepository.kt` busca `stickerclassification/lang/$lang.txt` y recurre a `en.txt` como alternativa para traducir etiquetas. Estos recursos de idioma no sustituyen al modelo de clasificación.

### Procedencia y límites de la CI

En `.github/workflows/pre_release.yml`, la CI obtiene un repositorio privado mediante `secrets.SECRET_REPO` y `secrets.TOKEN`. Desde `secret/Rays-Android` copia `key.jks` y `secret.gradle.kts` a la raíz del proyecto, y el directorio `assets` a `app/src/main`, antes de compilar `assembleGitHubRelease`. El workflow evidencia una provisión privada de assets, pero no permite confirmar desde este checkout el contenido exacto de ese repositorio.

Para validar las funciones de IA hacen falta recursos legítimos, compatibles con las interfaces de los modelos y con permisos/licencias adecuados, facilitados por sus responsables. Esta guía no descarga modelos, no los sustituye por archivos ficticios ni propone reutilizar credenciales o assets privados sin autorización. La ausencia de estos modelos es una limitación funcional en ejecución, no una demostración de que Gradle necesariamente falle al empaquetar.

## Alcance de las pruebas y de esta documentación

La prueba unitaria existente, `app/src/test/java/com/skyd/rays/ExampleUnitTest.kt`, solo comprueba `assertEquals(4, 2 + 2)` en `addition_isCorrect`. Es un ejemplo trivial: no valida inferencia, clasificación, similitud de imágenes, transferencia de estilo ni disponibilidad de modelos.

Esta documentación se contrastó con la configuración local, los scripts de Gradle, el workflow y el código de carga de assets. Resultados del 16 de noviembre de 2026:

- `devenv test`: correcto, Java 17 y herramientas Android disponibles.
- `./gradlew --version`: Gradle 8.13, JVM 17.
- Dependencias `GitHubDebugRuntimeClasspath`: resueltas, sin `FAILED`.
- `:app:assembleGitHubDebug :app:testGitHubDebugUnitTest`: `BUILD SUCCESSFUL`, con una prueba, cero fallos y cero errores.
- APK universal y cuatro APK específicos por ABI generados en la ruta indicada.
- `apksigner verify` del APK universal: correcto. `aapt dump badging` confirma `com.skyd.rays.debug`, API mínima 24 y SDK objetivo 35.

La primera ejecución agotó el límite de 10 minutos de la herramienta durante el procesamiento de clases. Una segunda ejecución incremental terminó correctamente en 2 minutos y 14 segundos, sin modificar el código de la aplicación ni actualizar dependencias.

Persisten advertencias no bloqueantes de APIs obsoletas, del opt-in de Coil, del namespace de LiteRT y de bibliotecas nativas empaquetadas sin eliminar símbolos. `sdkmanager 13.0` también avisa sobre metadatos SDK XML más recientes. El input fijado al tag Devenv `v2.2.2` declara internamente `2.2.1`, lo que produce un aviso de versión, sin impedir las pruebas. No se añadieron toolchains nativos únicamente para silenciar advertencias.

### Comprobaciones adicionales de integración

- Se copió únicamente `devenv.nix`, `devenv.yaml`, `devenv.lock` y `gradlew` a un directorio temporal independiente. `devenv test` pasó sin `secret.gradle.kts` ni fuentes de la aplicación y no creó `local.properties`, secretos ni un directorio `app`. Esto verifica que activar y comprobar el entorno no depende de credenciales ni inicia la compilación.
- Se repitió `:app:assembleGitHubDebug :app:testGitHubDebugUnitTest` con `--offline --no-daemon --max-workers=2`: `BUILD SUCCESSFUL` en 1 minuto y 5 segundos. Este resultado verifica la reutilización de las dependencias ya descargadas, no una descarga desde cero sin red.
- `:app:installGitHubDebug --dry-run --offline` resolvió correctamente su grafo de tareas. La instalación apareció como `SKIPPED`, sin contactar ni modificar un dispositivo. No sustituye una instalación real.
- Se verificó la firma de los cinco APK con `apksigner verify`. Los metadatos y bibliotecas nativas coinciden con cada ABI; el universal contiene `arm64-v8a`, `armeabi-v7a`, `x86` y `x86_64`. Todos declaran `com.skyd.rays.debug`, mínimo 24 y objetivo 35. Ningún APK contiene los archivos `secret.gradle.kts`, `key.jks` o `local.properties`.
- El contenido del archivo local de secretos permaneció intacto después de compilar y resolver la instalación. No se creó `local.properties` en el proyecto.
- Un chequeo automático contrastó las seis rutas `.tflite` literales de los tres cargadores Kotlin con la tabla de esta guía: coinciden exactamente. Se abrieron los cinco APK como ZIP y se confirmó que esas seis rutas no están empaquetadas, mientras `assets/stickerclassification/lang/en.txt` sí está presente. También se comprobó el destino del enlace desde README, la existencia de los archivos Kotlin citados y la sintaxis de todos los bloques `sh` con `bash -n`. Esto valida inventario y documentación, no la ejecución de inferencia en Android.

Los esquemas exportados automáticamente por Room en `app/schemas/` se mantienen locales y están excluidos de Git, al igual que las cachés y los APK. Queda pendiente la comprobación funcional en Android, especialmente las funciones de IA que requieren modelos ausentes.
