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
        throw error;
    }
    return result;
}

async function copyResourceRegistrationLink() {
    const url = new URL('register.html',location.href).href;
    try { await navigator.clipboard.writeText(url);alert('Registration link copied.'); }
    catch { prompt('Copy this registration link:',url); }
}

async function sendResourceAccessInvitation() {
    if (!resource?.email) return showError('Save an email address first.');
    if (!confirm(`Send a password setup link to ${resource.email}? External portal approval remains separate.`)) return;
    const button = document.getElementById('sendAccessInvitationBtn');
    if (button) button.disabled = true;
    try {
        await resourceOnboarding({action:'invite',resource_id:resourceId});
        await loadResource();
        alert('Invitation request accepted by the email service. Ask the recipient to check their inbox.');
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
    description.textContent = resource.profile_id
        ? `Account linked. Send a new password setup link to ${resource.email}.`
        : `No account yet. The invitation creates a login for ${resource.email || 'the saved email'}.`;
    document.getElementById('sendAccessInvitationBtn').disabled = !resource.email || resource.lifecycle_status === 'Inactive' || resource.portal_status === 'Closed';
}
