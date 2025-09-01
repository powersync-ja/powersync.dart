// Copy this template: `cp lib/app_config_template.dart lib/app_config.dart`
// Edit lib/app_config.dart and enter your Supabase and PowerSync project details.
class AppConfig {
  static const String supabaseUrl = 'https://foo.supabase.co';
  static const String supabaseAnonKey = 'foo';
  static const String powersyncUrl = 'https://foo.powersync.journeyapps.com';
  static const String supabaseStorageBucket =
      ''; // Optional. Only required when syncing attachments and using Supabase Storage. See packages/powersync_attachments_helper.
  // Whether the PowerSync instance uses sync streams to make fetching todo
  // items optional.
  static const bool hasSyncStreams = false;
}
