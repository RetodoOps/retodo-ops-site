const registrationForm = document.getElementById('registrationForm');
const registrationMessage = document.getElementById('registrationMessage');
const registerButton = document.getElementById('registerBtn');
const registrationSignInButton = document.getElementById('registrationSignIn');
const registrationResetButton = document.getElementById('registrationReset');
let completingRegistration = false;
let awaitingRegistrationAuth = false;
const REGISTRATION_NAME_KEY = 'tms-registration-name';
const REGISTRATION_EMAIL_KEY = 'tms-registration-email';
const REGISTRATION_RESET_KEY = 'tms-registration-reset-return';

const registrationCallback = () => {
    const query = new URLSearchParams(location.search);
    const hash = new URLSearchParams(location.hash.replace(/^#/, ''));
    return query.has('code') || query.get('password_reset') === 'complete'
        || hash.has('access_token') || ['signup', 'invite'].includes(hash.get('type'));
};

function isExistingAccountError(error) {
    return /already\s+(?:registered|exists|in use)|user\s+already|email\s+already/i.test(String(error?.message || error || ''));
}

function rememberRegistrationIdentity() {
    sessionStorage.setItem(REGISTRATION_NAME_KEY, document.getElementById('registrationName').value.trim());
    sessionStorage.setItem(REGISTRATION_EMAIL_KEY, document.getElementById('registrationEmail').value.trim().toLowerCase());
}

function rememberedRegistrationName(session) {
    return sessionStorage.getItem(REGISTRATION_NAME_KEY)
        || session?.user?.user_metadata?.full_name
        || document.getElementById('registrationName').value.trim();
}

function clearRememberedRegistrationIdentity() {
    sessionStorage.removeItem(REGISTRATION_NAME_KEY);
    sessionStorage.removeItem(REGISTRATION_EMAIL_KEY);
}

function showExistingAccountMessage() {
    setRegistrationMessage('This email already has an account. Use “Forgot password / send setup link” below, then return here and sign in with the new password.', true);
}

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
        const result = await resourceOnboarding({action:'register', name:rememberedRegistrationName(session)});
        setRegistrationMessage(result.pending_approval
            ? 'Registration completed. Your account is awaiting Administrator approval.'
            : 'Registration completed. You can now sign in to your portal.');
        clearRememberedRegistrationIdentity();
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
    rememberRegistrationIdentity();
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
            document.getElementById('registrationPassword').value = '';
            document.getElementById('registrationConfirm').value = '';
            showExistingAccountMessage();
        } else {
            setRegistrationMessage(`Confirmation sent to ${email}. Open the newest email to complete registration.`);
        }
    } catch (error) {
        document.getElementById('registrationPassword').value = '';
        document.getElementById('registrationConfirm').value = '';
        if (isExistingAccountError(error)) showExistingAccountMessage();
        else setRegistrationMessage(error.message || 'Registration could not be completed. Try again.', true);
    } finally {
        awaitingRegistrationAuth = false;
        setRegistrationBusy(false);
    }
});

registrationSignInButton.addEventListener('click', async () => {
    registrationForm.classList.remove('hidden');
    const email = document.getElementById('registrationEmail').value.trim().toLowerCase();
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
        const detail = String(error?.message || '');
        setRegistrationMessage(/invalid login credentials/i.test(detail)
            ? 'Invalid login credentials. This is the existing account password, not the password from the rejected sign-up. Use “Forgot password / send setup link” below if needed.'
            : /email not confirmed/i.test(detail)
                ? 'This account still needs email confirmation. Open the newest confirmation email, then return here and sign in.'
                : detail || 'Sign in could not be completed.', true);
    } finally { awaitingRegistrationAuth = false; }
});

registrationResetButton.addEventListener('click', async () => {
    const emailInput = document.getElementById('registrationEmail');
    if (!emailInput.value.trim() || !emailInput.checkValidity()) {
        setRegistrationMessage('Enter the existing email address first, then request the password setup link.', true);
        emailInput.focus();
        return;
    }
    const email = emailInput.value.trim().toLowerCase();
    rememberRegistrationIdentity();
    sessionStorage.setItem(REGISTRATION_RESET_KEY, 'register');
    registrationResetButton.disabled = true;
    registrationResetButton.textContent = 'Sending setup link…';
    try {
        const {error} = await requestPasswordReset(email);
        if (error) throw error;
        setRegistrationMessage(`If this address belongs to a TMS account, a password setup link has been sent to ${email}. Open it, save the new password, then return here to finish registration.`);
    } catch (error) {
        setRegistrationMessage('The password setup link could not be sent. Check the address and try again.', true);
    } finally {
        registrationResetButton.disabled = false;
        registrationResetButton.textContent = 'Forgot password / send setup link';
    }
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
