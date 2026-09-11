async function resourceOnboarding(payload) {
    const {data:{session}} = await _sb.auth.getSession();
    if (!session) throw new Error('Sign in first.');
    const response = await fetch('/.netlify/functions/resource-onboarding', {
        method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${session.access_token}`},
        body:JSON.stringify(payload)
    });
    const result = await response.json().catch(()=>({error:'Onboarding service is unavailable.'}));
    if (!response.ok) {
        const error = new Error(result.error || 'Onboarding failed.');
        error.resourceId = result.resource_id;
        error.emailCorrected = result.email_corrected === true;
        error.emailCorrectionPending = result.email_correction_pending === true;
        throw error;
    }
    return result;
}

const invitationEmailDomainTypos = new Map([
    ['gmai.com','gmail.com'],['gmial.com','gmail.com'],['gamil.com','gmail.com'],
    ['gmail.con','gmail.com'],['hotnail.com','hotmail.com'],
    ['outlok.com','outlook.com'],['yaho.com','yahoo.com']
]);
const normalizeInvitationEmail = value => String(value ?? '').trim().toLowerCase();
function invitationEmailProblem(value) {
    const email = normalizeInvitationEmail(value);
    if (!email || email.length > 320 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        return 'Enter a valid recipient email address.';
    }
    const domain = email.slice(email.lastIndexOf('@') + 1);
    const suggestion = invitationEmailDomainTypos.get(domain);
    return suggestion ? `The email domain “${domain}” looks mistyped. Did you mean “${suggestion}”?` : '';
}
function requestExactEmailConfirmation(email, purpose) {
    const normalized = normalizeInvitationEmail(email);
    const problem = invitationEmailProblem(normalized);
    if (problem) throw new Error(problem);
    const confirmation = prompt(`${purpose}\n\nType the full recipient email address to confirm:\n${normalized}`);
    if (confirmation === null) return null;
    if (normalizeInvitationEmail(confirmation) !== normalized) {
        throw new Error('The confirmation did not exactly match the recipient email. Nothing was sent.');
    }
    return normalized;
}

async function copyResourceRegistrationLink() {
    const url = new URL('register.html',location.href).href;
    try { await navigator.clipboard.writeText(url);alert('Registration link copied.'); }
    catch { prompt('Copy this registration link:',url); }
}

async function sendResourceAccessInvitation() {
    if (!resource?.email) return showError('Save an email address first.');
    const workspaceName = resource.resource_type === 'Internal' ? 'company TMS workspace' : 'Resource Portal';
    let confirmedEmail;
    try {
        confirmedEmail = requestExactEmailConfirmation(resource.email,
            `Send an access invitation to this address? The recipient will choose a password and then open the ${workspaceName}.`);
    } catch (error) { return showError(error.message); }
    if (!confirmedEmail) return;
    const button = document.getElementById('sendAccessInvitationBtn');
    if (button) button.disabled = true;
    try {
        await resourceOnboarding({action:'invite',resource_id:resourceId,confirmed_email:confirmedEmail});
        await loadResource();
        alert(`Access invitation sent. Ask the recipient to open the newest email, choose a password and continue to the ${workspaceName}.`);
    } catch (error) { showError(error.message); }
    finally { if (button) button.disabled = false; }
}

function renderAccessInvitation() {
    let block = document.getElementById('accessInvitationBlock');
    if (!block) {
        block = document.createElement('div');
        block.id = 'accessInvitationBlock';
        block.className = 'portal-link-card';
        block.innerHTML = '<div><strong>Account invitation</strong><span id="accessInvitationDescription"></span></div><button type="button" id="sendAccessInvitationBtn" class="btn-primary">Send access invitation</button>';
        block.querySelector('button').addEventListener('click',sendResourceAccessInvitation);
    }
    const internal = resource.resource_type === 'Internal';
    document.getElementById(internal ? 'internalOverviewCard' : 'pane-portal').append(block);
    const allowed = internal ? ['admin','pm','client_relations'].includes(appRole) : appRole === 'admin';
    block.classList.toggle('hidden',!allowed);
    const description = document.getElementById('accessInvitationDescription');
    const workspaceName = internal ? 'company TMS workspace' : 'Resource Portal';
    description.textContent = resource.profile_id
        ? `Account linked. A new invitation lets ${resource.email} choose a password and open the ${workspaceName}.`
        : `The invitation creates a login for ${resource.email || 'the saved email'}, then opens the ${workspaceName} after password setup.`;
    document.getElementById('sendAccessInvitationBtn').disabled = !resource.email || resource.lifecycle_status === 'Inactive' || resource.portal_status === 'Closed';
}
