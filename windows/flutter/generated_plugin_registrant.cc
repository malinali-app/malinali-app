//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <ffmpeg_kit_flutter_new_audio/f_fmpeg_kit_flutter_plugin.h>
#include <file_selector_windows/file_selector_windows.h>
#include <flutter_tts/flutter_tts_plugin.h>
#include <just_audio_windows_plus/just_audio_windows_plus_plugin.h>
#include <permission_handler_windows/permission_handler_windows_plugin.h>
#include <record_windows/record_windows_plugin_c_api.h>
#include <share_plus/share_plus_windows_plugin_c_api.h>
#include <url_launcher_windows/url_launcher_windows.h>
#include <vosk_flutter/vosk_flutter_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  FFmpegKitFlutterPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FFmpegKitFlutterPlugin"));
  FileSelectorWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FileSelectorWindows"));
  FlutterTtsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterTtsPlugin"));
  JustAudioWindowsPlusPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("JustAudioWindowsPlusPlugin"));
  PermissionHandlerWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("PermissionHandlerWindowsPlugin"));
  RecordWindowsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("RecordWindowsPluginCApi"));
  SharePlusWindowsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("SharePlusWindowsPluginCApi"));
  UrlLauncherWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("UrlLauncherWindows"));
  VoskFlutterPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("VoskFlutterPlugin"));
}
