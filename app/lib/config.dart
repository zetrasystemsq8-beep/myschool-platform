/// Public client configuration. The anon key is designed to be public: it only
/// works within the limits of the database's Row Level Security.
/// NEVER put the service_role key or the database password in this app.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://rxxaccwqfboeibjhlawh.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ4eGFjY3dxZmJvZWliamhsYXdoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM3MTI1OTMsImV4cCI6MjA5OTI4ODU5M30.a0WBtyRM8QhuX3VsvCUBUz9FP8rbEsCZIifSsKy_enI',
  );

  /// All MySchool tables/RPCs live in this Postgres schema.
  static const schema = 'myschool';
  static const logoBucket = 'myschool-logos';
}
