const registrationForm = document.getElementById('registrationForm');
const registrationMessage = document.getElementById('registrationMessage');
let completingRegistration = false;
async function finishRegistration(session) {
    if (!session || completingRegistration) return;
    completingRegistration = true;
    registrationForm.classList.add('hidden');
    registrationMessage.textContent = 'Completing your registration…';
    try {
        const result = await resourceOnboarding({action:'register',name:session.user.user_metadata?.full_name || ''});
        registrationMessage.textContent = result.pending_approval
            ? 'Registration completed. Your account is awaiting Administrator approval.'
            : 'Registration completed. You can now sign in to your portal.';
        await _sb.auth.signOut();
    } catch (error) {
        registrationMessage.textContent = `${error.message} Reload this page to retry without creating another account.`;
        completingRegistration = false;
    }
}
registrationForm.addEventListener('submit', async event => {
    event.preventDefault();
    const password = document.getElementById('registrationPassword').value;
    if (password !== document.getElementById('registrationConfirm').value) {
        registrationMessage.textContent = 'Passwords do not match.';return;
    }
    const button = document.getElementById('registerBtn');button.disabled = true;
    try {
        const {data,error} = await _sb.auth.signUp({
            email:document.getElementById('registrationEmail').value.trim(),password,
            options:{emailRedirectTo:new URL('register.html',location.href).href,
                data:{full_name:document.getElementById('registrationName').value.trim()}}
        });
        if (error) throw error;
        document.getElementById('registrationPassword').value = '';
        document.getElementById('registrationConfirm').value = '';
        if (data.session) await finishRegistration(data.session);
        else registrationMessage.textContent = 'Check your email to confirm registration. If you already have an account, use Sign in or Forgot password.';
    } catch (error) { registrationMessage.textContent = error.message; }
    finally { button.disabled = false; }
});
document.getElementById('registrationSignIn').addEventListener('click',async()=>{
    registrationForm.classList.remove('hidden');
    const email=document.getElementById('registrationEmail').value.trim();
    const password=document.getElementById('registrationPassword').value;
    if (!email || !password) {registrationMessage.textContent='Enter your existing email and password above, then click Sign in to finish registration.';return;}
    const {data,error}=await _sb.auth.signInWithPassword({email,password});
    if (error) {registrationMessage.textContent=error.message;return;}
    await finishRegistration(data.session);
});
// Schedule outside the Auth callback to avoid Supabase auth-lock deadlocks.
_sb.auth.onAuthStateChange((event,session)=>{
    if (session && ['SIGNED_IN','INITIAL_SESSION'].includes(event)) setTimeout(()=>finishRegistration(session),0);
});
