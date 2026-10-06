'use strict';

// Only these reviewed messages may bypass the general error redactor. Provider
// descriptions, response bodies and environment values are never interpolated.
const messages=Object.freeze({
  GOOGLE_CONFIG_MISSING:'Google mail setup is incomplete. Configure GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET and GOOGLE_REFRESH_TOKEN in the Netlify production function environment.',
  GOOGLE_CONFIG_FORMAT:'A Google mail setting contains quotation marks, JSON or internal whitespace. Paste only the plain value into each Netlify variable, save and deploy again.',
  GOOGLE_CLIENT_REJECTED:'Google rejected the OAuth client (invalid_client). Check that GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in Netlify match the same OAuth client used in OAuth Playground.',
  GOOGLE_REFRESH_REJECTED:'Google rejected the refresh token (invalid_grant). It may be expired, revoked or issued to another OAuth client. Use the same client ID and secret as Netlify when renewing access. If the token works in OAuth Playground, check the Netlify production value and deploy again.',
  GOOGLE_CLIENT_NOT_ALLOWED:'Google does not allow this OAuth client to refresh access (unauthorized_client). Check the existing web-application client and Google Workspace app-access policy.',
  GOOGLE_POLICY_BLOCKED:'Google blocked the mail connection under an account or administrator policy. Review this app with the Google Workspace administrator.',
  GOOGLE_TOKEN_REQUEST_INVALID:'Google rejected the token request (invalid_request). Check the three Google mail variables are plain values from the same OAuth client and use the refresh token, not the access token.',
  GOOGLE_TOKEN_RESPONSE_INVALID:'Google did not return a usable access token. Review the OAuth client and deployed Netlify mail configuration. No message was sent by this connection check.',
  GOOGLE_TEMPORARILY_UNAVAILABLE:'Google temporarily refused the request or rate-limited it. Wait briefly, then check the mailbox connection again.',
  GOOGLE_CONNECTION_TIMEOUT:'The Google mail request timed out. Check the mailbox connection again; this result does not establish that the saved token is invalid.',
  GOOGLE_CONNECTION_FAILED:'The function could not reach Google. Check the mailbox connection again; if it persists, review Netlify function connectivity.',
  GMAIL_API_DISABLED:'The Gmail API is disabled for the OAuth project. Enable Gmail API in the Google Cloud project containing the existing OAuth client, then check again.',
  GMAIL_PERMISSIONS_MISSING:'Gmail denied the request because permissions are missing (HTTP 403). Authorize both gmail.send and gmail.readonly with the existing OAuth client, save the resulting refresh token in Netlify and deploy again.',
  GMAIL_API_FORBIDDEN:'Gmail denied access (HTTP 403). Check Gmail API is enabled, the account has Gmail access, both gmail.send and gmail.readonly were granted, and the Workspace app policy permits access.',
  GMAIL_ACCESS_REJECTED:'Gmail rejected the access token (HTTP 401). Check the mailbox authorization and retry the connection check.',
  GMAIL_REQUEST_FAILED:'The Gmail API request failed. Check the mailbox connection and account access before continuing.',
  GOOGLE_MAILBOX_MISMATCH:'The connected Gmail account does not match the Sales mailbox. Set SALES_GMAIL_ACCOUNT_EMAIL to the primary account used for OAuth, or reconnect the intended mailbox.',
  GOOGLE_ALIAS_UNVERIFIED:'Eli’s Sales alias is missing or is not verified in the connected mailbox. Check eli.s@retodo-ops.com is an accepted send-as address in that mailbox.'
});

function diagnostic(code) {
  if(typeof code!=='string' || !Object.hasOwn(messages,code))return null;
  return {code,error:`[${code}] ${messages[code]}`};
}

function connectionError(code) {
  const detail=diagnostic(code)||diagnostic('GMAIL_REQUEST_FAILED');
  const error=new Error(detail.error);
  error.salesConnectionCode=detail.code;
  return error;
}

module.exports={connectionError,diagnostic};
