'use strict';

// Renderer IPC cannot bypass the missing secure identity/consent flow. Public
// discovery is the only allowed rail operation in this build; no arbitrary URL,
// identity lookup, signed/unsigned submission, legacy fallback or payout request.
function allowedRailRead(endpoint, options = {}) {
  return typeof endpoint === 'string'
    && ['/api/offers/available', '/api/updates/latest'].includes(endpoint)
    && options !== null && typeof options === 'object' && !Array.isArray(options)
    && (options.method === undefined || options.method === 'GET')
    && Object.keys(options).every(key => key === 'method');
}
module.exports = { allowedRailRead };
