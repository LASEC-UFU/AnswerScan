# answer_scan

Aplicativo Flutter para leitura offline de gabarito fixo com 20 questoes x 5 alternativas.

## Arquitetura

- Flutter: UI, fluxo de captura/galeria e exibicao do resultado.
- Kotlin nativo no Android: pipeline de visao computacional.
- OpenCV no Android: threshold, contornos, homografia, ROIs e score.
- Platform Channel: `com.example.answer_scan/omr`.
- Offline: sem backend, sem OCR, sem Python.

## Pipeline nativo

1. Flutter captura ou seleciona a imagem.
2. O caminho da imagem vai para o Kotlin via `MethodChannel`.
3. O Android executa:
   - grayscale
   - blur leve
   - threshold adaptativo + Otsu
   - deteccao dos 4 marcadores
   - homografia para tamanho fixo
   - leitura por grid fixo
   - classificacao de cada questao em `A-E`, `blank`, `multiple` ou `ambiguous`
4. O resultado volta para o Flutter como `Map`, convertido em `OmrScanResult`.

## Instalacao Android + OpenCV

### Requisitos

- Flutter SDK
- Android SDK
- JDK 17 ou superior

### JDK

O Android Gradle Plugin deste projeto exige Java 17+.

No Windows PowerShell:

```powershell
$env:JAVA_HOME='C:\Program Files\Java\jdk-21'
$env:Path='C:\Program Files\Java\jdk-21\bin;' + $env:Path
```

Se preferir fixar no Gradle, ajuste `android/gradle.properties` com `org.gradle.java.home`.

### OpenCV

Nao ha SDK manual para baixar.

O OpenCV ja esta integrado por Maven em `android/app/build.gradle.kts`:

```kotlin
dependencies {
    implementation("org.opencv:opencv:4.9.0")
}
```

E a inicializacao ocorre em `MainActivity.kt` com:

```kotlin
OpenCVLoader.initLocal()
```

### Instalar dependencias e rodar

```powershell
flutter pub get
flutter run
```

### Build Android

```powershell
cd android
.\gradlew.bat app:assembleDebug
```

## Modo debug

Na tela principal, habilite `Salvar debug nativo`.

O scanner passa a salvar uma imagem `_omr_debug.jpg` com:

- cantos detectados
- imagem apos homografia
- ROIs da grade
- scores por alternativa

Tambem existe a tela `Diagnostico nativo` para capturar ou carregar uma folha e inspecionar o retorno completo do pipeline.

## Lancamento de notas no Moodle

O aplicativo suporta leitura e atualizacao direta de notas de atividades do
tipo **Tarefa (Assignment)**. O fluxo utiliza:

- `mod_assign_get_assignments` para listar as atividades.
- `gradereport_user_get_grade_items` para buscar a nota exibida no livro.
- `core_grades_update_grades` para lancamento direto no livro de notas.
- `mod_assign_get_grades` e `mod_assign_save_grade` como compatibilidade para
  Tarefas quando os endpoints diretos nao estiverem disponiveis.

Para o fluxo recomendado, `gradereport_user_get_grade_items` e
`core_grades_update_grades` devem estar disponiveis no Servico Externo usado
pelo token, e o professor precisa ter permissao para atribuir notas. Depois de
salvar, o aplicativo rele a nota no livro e somente confirma sucesso quando o
valor persistido corresponde ao valor enviado.

Itens manuais do livro de notas e atividades de outros modulos, como
Questionario, nao usam `mod_assign_save_grade` e nao sao exibidos neste fluxo.
Esses tipos exigem endpoints e permissoes diferentes. O painel
`Diagnostico Moodle` na tela de nota manual mostra as chamadas, IDs, respostas
e erros recebidos sem exibir o token de acesso.

## Pontos de calibracao do template

### Geometria do template

Arquivo: `android/app/src/main/kotlin/com/example/answer_scan/omr/TemplateConfig.kt`

- `HEADER_HEIGHT_FRAC`
- `LABEL_WIDTH_FRAC`
- `CELL_READ_FRAC`
- `CELL_CORE_FRAC`

### Limiares de classificacao

Arquivo: `android/app/src/main/kotlin/com/example/answer_scan/omr/TemplateConfig.kt`

- `BLANK_THRESHOLD`
- `FILL_THRESHOLD`
- `MULTIPLE_THRESHOLD`
- `DOMINANCE_DELTA`
- `GAP_RATIO`

### Robustez de deteccao dos marcadores

Arquivo: `android/app/src/main/kotlin/com/example/answer_scan/omr/TemplateConfig.kt`

- `MARKER_MIN_AREA_FRAC`
- `MARKER_MAX_AREA_FRAC`
- `MARKER_MIN_SOLIDITY`
- `MARKER_MIN_DENSITY`
- `MARKER_MIN_ASPECT`
- `MARKER_MAX_ASPECT`
- `MARKER_CORNER_REGION_FRAC`

## Arquivos principais

- `lib/presentation/pages/home_page.dart`
- `lib/presentation/pages/camera_capture_page.dart`
- `lib/presentation/pages/calibration_page.dart`
- `lib/presentation/controllers/correction_controller.dart`
- `lib/data/services/omr_native_channel.dart`
- `android/app/src/main/kotlin/com/example/answer_scan/MainActivity.kt`
- `android/app/src/main/kotlin/com/example/answer_scan/omr/TemplateScanner.kt`
- `android/app/src/main/kotlin/com/example/answer_scan/omr/MarkerDetector.kt`
- `android/app/src/main/kotlin/com/example/answer_scan/omr/PerspectiveCorrector.kt`
- `android/app/src/main/kotlin/com/example/answer_scan/omr/GridMapper.kt`
- `android/app/src/main/kotlin/com/example/answer_scan/omr/AnswerReader.kt`
- `android/app/src/main/kotlin/com/example/answer_scan/omr/ScanResultMapper.kt`
- `android/app/src/main/kotlin/com/example/answer_scan/omr/OmrDebugHelper.kt`
