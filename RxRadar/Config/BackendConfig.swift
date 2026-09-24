import Foundation

/// Connection info for the shared "community reports" database (Supabase).
///
/// Leave these empty and the app works in "this iPhone only" mode.
/// To connect: create a free project at supabase.com, run `backend/supabase-setup.sql`,
/// then paste the Project URL and the publishable (anon) key below.
/// See backend/README.md for step-by-step instructions.
///
/// The publishable key is designed to be public — it can only do what the
/// database rules in supabase-setup.sql allow (read recent reports, add new ones).
enum BackendConfig {
    static let supabaseURL = "https://bvlfogttapmohgyvvyva.supabase.co"
    static let supabasePublishableKey = "sb_publishable_dFeIfmrL2FZintNJE4yxJQ_kX7fS4GJ"
}
