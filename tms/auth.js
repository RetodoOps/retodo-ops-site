const _sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

async function checkSession() {
    const { data: { session } } = await _sb.auth.getSession();
    return session?.user ?? null;
}

async function requireAuth() {
    const user = await checkSession();
    if (!user) { window.location.href = 'index.html'; return null; }
    return user;
}

async function signIn(email, password) {
    return _sb.auth.signInWithPassword({ email, password });
}

async function signOut() {
    await _sb.auth.signOut();
    window.location.href = 'index.html';
}
