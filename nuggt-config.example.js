// Copy values into nuggt-config.js before deploying Weather to production.
//
// On the Nuggt server you also need:
//   1. MANIFEST_PUBLISH_API_KEY=<same key as below>
//   2. MANIFEST_PUBLISH_ORIGINS=https://edconway.github.io  (or your Weather URL origin)
//
// Local dev (Nuggt API on localhost:8000, key unset): leave NUGGT_PUBLISH_KEY empty.

window.NUGGT_API_BASE = 'https://nuggt.com';
window.NUGGT_PUBLISH_KEY = 'paste-your-publish-key-here';

// Quick test without editing this file (browser console):
//   localStorage.setItem('nuggt-publish-key', 'your-key');
//   location.reload();
