const registrationForm = document.getElementById('registrationForm');
const registrationMessage = document.getElementById('registrationMessage');
const registerButton = document.getElementById('registerBtn');
let completingRegistration = false;
let awaitingRegistrationAuth = false;

const registrationCallback = () => {
    const query = new URLSearchParams(location.search);
    const hash = new URLSearchParams(location.hash.replace(/^#/, ''));
    return query.has('code') || hash.has('access_token') || ['signup', 'invite'].includes(hash.get('type'));
};

function setRegistrationMessage(message, isError = false) {
    registrationMessage.textContent = message;
    registrationMessage.classList.toggle('error-msg', isError);
    registrationMessage.classList.toggle('registration-success', !isError && !!message);
}

function setRegistrationBusy(busy) {
    registerButton.disabled = busy;
    registerButton.textContent = busy ? 'Creating account…' : 'Create account';
}

async function finishRegistration(session) {
    if (!session || completingRegistration) return;
    completingRegistration = true;
    registrationForm.classList.add('hidden');
    setRegistrationMessage('Completing your registration…');
    try {
        const result = await resourceOnboarding({action:'register', name:session.user.user_metadata?.full_name || ''});
        setRegistrationMessage(result.pending_approval
            ? 'Registration completed. Your account is awaiting Administrator approval.'
            : 'Registration completed. You can now sign in to your portal.');
        await _sb.auth.signOut();
    } catch (error) {
        registrationForm.classList.remove('hidden');
        setRegistrationMessage(`${error.message} Reload this page to retry without creating another account.`, true);
        completingRegistration = false;
    }
}

registrationForm.addEventListener('submit', async event => {
    event.preventDefault();
    setRegistrationMessage('');
    if (!registrationForm.reportValidity()) return;
    const password = document.getElementById('registrationPassword').value;
    if (password !== document.getElementById('registrationConfirm').value) {
        setRegistrationMessage('Passwords do not match.', true);
        return;
    }
    setRegistrationBusy(true);
    awaitingRegistrationAuth = true;
    try {
        const existing = (await _sb.auth.getSession()).data.session;
        if (existing) await _sb.auth.signOut();
        const email = document.getElementById('registrationEmail').value.trim();
        const {data, error} = await _sb.auth.signUp({
            email,
            password,
            options:{
                emailRedirectTo:new URL('register.html', location.href).href,
                data:{full_name:document.getElementById('registrationName').value.trim()},
            },
        });
        if (error) throw error;
        document.getElementById('registrationPassword').value = '';
        document.getElementById('registrationConfirm').value = '';
        if (data.session) await finishRegistration(data.session);
        else if (Array.isArray(data.user?.identities) && data.user.identities.length === 0) {
            setRegistrationMessage('An account already exists for this email. Use Sign in below or Forgot password on the TMS sign-in page.', true);
        } else {
            setRegistrationMessage(`Confirmation sent to ${email}. Open the newest email to complete registration.`);
        }
    } catch (error) {
        setRegistrationMessage(error.message || 'Registration could not be completed. Try again.', true);
    } finally {
        awaitingRegistrationAuth = false;
        setRegistrationBusy(false);
    }
});

document.getElementById('registrationSignIn').addEventListener('click', async () => {
    registrationForm.classList.remove('hidden');
    const email = document.getElementById('registrationEmail').value.trim();
    const password = document.getElementById('registrationPassword').value;
    if (!email || !password) {
        setRegistrationMessage('Enter your existing email and password above, then click Sign in to finish registration.', true);
        return;
    }
    awaitingRegistrationAuth = true;
    try {
        const {data, error} = await _sb.auth.signInWithPassword({email, password});
        if (error) throw error;
        await finishRegistration(data.session);
    } catch (error) {
        setRegistrationMessage(error.message, true);
    } finally { awaitingRegistrationAuth = false; }
});

_sb.auth.onAuthStateChange((event, session) => {
    if (session && (awaitingRegistrationAuth || registrationCallback())
        && ['SIGNED_IN', 'INITIAL_SESSION'].includes(event)) {
        setTimeout(() => finishRegistration(session), 0);
    }
});

(async () => {
    const session = (await _sb.auth.getSession()).data.session;
    if (!session) return;
    if (registrationCallback()) await finishRegistration(session);
    else {
        await _sb.auth.signOut();
        setRegistrationMessage('Your existing TMS session was signed out. Complete the form to create a separate Resource account.');
    }
})();
