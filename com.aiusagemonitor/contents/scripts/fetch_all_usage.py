#!/usr/bin/env python3
"""
AI Usage Monitor - Data fetcher
Reads usage data for Claude Code, OpenAI Codex, and Gemini CLI.
Outputs a single JSON object to stdout.
"""
import json
import glob
from datetime import datetime, timezone
from pathlib import Path
import urllib.request
import urllib.error
import urllib.parse
import socket
import sys

result = {}
today = datetime.now(timezone.utc).date()

# Optional provider filter: python3 fetch_all_usage.py [claude|codex|gemini]
_only = sys.argv[1] if len(sys.argv) > 1 else None


def unix_to_iso(ts):
    """Convert Unix timestamp (int) to ISO 8601 string."""
    if ts is None:
        return None
    try:
        return datetime.fromtimestamp(int(ts), tz=timezone.utc).isoformat()
    except Exception:
        return str(ts)


def read_http_error_body(err):
    """Read and decode HTTP error body safely."""
    try:
        body = err.read()
        if isinstance(body, bytes):
            return body.decode('utf-8', errors='replace')
        return str(body or '')
    except Exception:
        return ''


def extract_api_message(body):
    """Extract a useful API message from JSON/text error bodies."""
    if not body:
        return ''
    try:
        obj = json.loads(body)
        if isinstance(obj, dict):
            if isinstance(obj.get('error'), dict):
                err = obj['error']
                return str(err.get('message') or err.get('status') or '').strip()
            return str(obj.get('message') or '').strip()
    except Exception:
        pass
    return body.strip().splitlines()[0][:180]


def classify_http_failure(provider, code, body='', context=None):
    """
    Normalize HTTP failures into user-facing messages.
    SECURITY: Never exposes full error bodies that might contain sensitive data.
    """
    context = context or {}
    api_msg = extract_api_message(body)
    fail_reason = 'http_error'
    error = f'HTTP {code}'

    if code == 401:
        fail_reason = 'auth_required'
        error = 'Authentication required'
    elif code == 403:
        fail_reason = 'forbidden'
        error = 'Permission denied'
    elif code == 404:
        fail_reason = 'not_found'
        error = 'API endpoint not found'
    elif code == 429:
        fail_reason = 'rate_limited'
        error = 'Rate limited'
    elif 500 <= code <= 599:
        fail_reason = 'server_error'
        error = 'Provider service error'

    # Add safe API message if available (already sanitized by extract_api_message)
    if api_msg:
        error = f'{error}: {api_msg}'

    return {
        'fail_reason': fail_reason,
        'http_code': code,
        'error': error,
    }


def classify_exception_failure(err):
    """Normalize non-HTTP failures."""
    if isinstance(err, urllib.error.URLError):
        reason = getattr(err, 'reason', None)
        if isinstance(reason, (TimeoutError, socket.timeout)):
            return {'fail_reason': 'timeout', 'error': 'Request timed out'}
        return {'fail_reason': 'network_error', 'error': f'Network error: {reason}'}
    if isinstance(err, TimeoutError):
        return {'fail_reason': 'timeout', 'error': 'Request timed out'}
    if isinstance(err, KeyError):
        return {'fail_reason': 'invalid_credentials', 'error': f'Missing credential field: {err}'}
    return {'fail_reason': 'unknown_error', 'error': str(err)}


def refresh_gemini_token(creds_path, creds):
    """
    Refresh Gemini OAuth token using refresh_token.
    Returns (success: bool, new_creds: dict | None, error_msg: str | None)

    SECURITY: This function handles sensitive credentials but never logs or outputs them.
    Only safe error messages are returned.
    """
    try:
        refresh_token = creds.get('refresh_token')
        client_id = creds.get('client_id')
        client_secret = creds.get('client_secret')

        if not refresh_token:
            return False, None, 'No refresh token found'
        if not client_id or not client_secret:
            return False, None, 'Missing OAuth client credentials'

        # Google OAuth2 token endpoint
        token_url = 'https://oauth2.googleapis.com/token'
        data = urllib.parse.urlencode({
            'client_id': client_id,
            'client_secret': client_secret,
            'refresh_token': refresh_token,
            'grant_type': 'refresh_token',
        }).encode()

        req = urllib.request.Request(token_url, data=data, headers={'Content-Type': 'application/x-www-form-urlencoded'})
        with urllib.request.urlopen(req, timeout=10) as resp:
            token_data = json.loads(resp.read())

        # Update credentials with new access token
        new_creds = creds.copy()
        new_creds['access_token'] = token_data['access_token']

        # Update expiry if provided
        if 'expires_in' in token_data:
            new_creds['expiry'] = int(datetime.now(timezone.utc).timestamp()) + token_data['expires_in']

        # Save updated credentials back to file (SECURITY: only write to user's home dir)
        creds_path.write_text(json.dumps(new_creds, indent=2))

        return True, new_creds, None

    except urllib.error.HTTPError as e:
        # SECURITY: Never expose the actual error body as it might contain sensitive info
        if e.code == 400:
            return False, None, 'Refresh token expired - please re-authenticate Gemini CLI'
        elif e.code == 401:
            return False, None, 'Authentication failed - please re-authenticate Gemini CLI'
        else:
            return False, None, f'Token refresh failed (HTTP {e.code})'
    except Exception as e:
        # SECURITY: Only expose safe error types, not full exception details
        err_type = type(e).__name__
        return False, None, f'Token refresh error: {err_type}'


# ── CLAUDE CODE ──────────────────────────────────────────────────────────────
if not _only or _only == 'claude':
    claude_creds_path = Path.home() / '.claude' / '.credentials.json'
    if claude_creds_path.exists():
        try:
            creds = json.loads(claude_creds_path.read_text())
            token = creds['claudeAiOauth']['accessToken']
            req = urllib.request.Request(
                'https://api.anthropic.com/api/oauth/usage',
                headers={
                    'Authorization': f'Bearer {token}',
                    'anthropic-beta': 'oauth-2025-04-20',
                    'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
                }
            )
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = json.loads(resp.read())

            five_hour = data.get('five_hour') or {}
            seven_day = data.get('seven_day') or {}

            result['claude'] = {
                'installed': True,
                'five_hour_pct': round(five_hour.get('utilization') or 0),
                'five_hour_reset': five_hour.get('resets_at'),
                'seven_day_pct': round(seven_day.get('utilization') or 0) if seven_day else None,
                'seven_day_reset': seven_day.get('resets_at') if seven_day else None,
            }
        except urllib.error.HTTPError as e:
            result['claude'] = {
                'installed': True,
                **classify_http_failure('claude', e.code, read_http_error_body(e)),
            }
        except Exception as e:
            result['claude'] = {'installed': True, **classify_exception_failure(e)}
    else:
        result['claude'] = {'installed': False}


# ── OPENAI CODEX ─────────────────────────────────────────────────────────────
if not _only or _only == 'codex':
    codex_sessions_dir = Path.home() / '.codex' / 'sessions'
    if codex_sessions_dir.exists():
        files = sorted(glob.glob(str(codex_sessions_dir / '**' / '*.jsonl'), recursive=True))
        if files:
            last_tc_payload = None
            last_model = ''

            for sf in reversed(files):
                main_in_file = None
                fallback_in_file = None
                try:
                    with open(sf, errors='replace') as f:
                        for line in f:
                            line = line.strip()
                            if not line:
                                continue
                            try:
                                obj = json.loads(line)
                                if obj.get('type') == 'event_msg':
                                    payload = obj.get('payload') or {}
                                    if payload.get('type') == 'token_count':
                                        lid = (payload.get('rate_limits') or {}).get('limit_id', '')
                                        if lid == 'codex':
                                            main_in_file = payload
                                        elif payload.get('rate_limits') is not None:
                                            # Only use as fallback if rate_limits is not null
                                            fallback_in_file = payload
                                elif obj.get('type') == 'turn_context':
                                    m = (obj.get('payload') or {}).get('model', '')
                                    if m:
                                        last_model = m
                            except json.JSONDecodeError:
                                continue
                except OSError:
                    continue

                chosen = main_in_file or fallback_in_file
                if chosen:
                    last_tc_payload = chosen
                    break

            if last_tc_payload:
                rl = last_tc_payload.get('rate_limits') or {}
                primary = rl.get('primary') or {}
                secondary = rl.get('secondary') or {}
                result['codex'] = {
                    'installed': True,
                    'five_hour_pct': primary.get('used_percent', 0),
                    'seven_day_pct': secondary.get('used_percent', 0),
                    'five_hour_reset': unix_to_iso(primary.get('resets_at')),
                    'seven_day_reset': unix_to_iso(secondary.get('resets_at')),
                    'plan_type': rl.get('plan_type') or '',
                    'model': last_model,
                }
            else:
                result['codex'] = {'installed': True, 'has_data': False}
        else:
            result['codex'] = {'installed': True, 'has_data': False}
    else:
        result['codex'] = {'installed': False}


# ── GEMINI CLI ────────────────────────────────────────────────────────────────
if not _only or _only == 'gemini':
    gemini_creds_path = Path.home() / '.gemini' / 'oauth_creds.json'
    if gemini_creds_path.exists():
        creds = {}
        max_retries = 3
        retry_count = 0
        last_error = None

        while retry_count < max_retries:
            try:
                creds = json.loads(gemini_creds_path.read_text())
                token = creds['access_token']

                base = 'https://cloudcode-pa.googleapis.com/v1internal'
                headers = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}

                load_body = json.dumps({
                    'cloudaicompanionProject': None,
                    'metadata': {'ideType': 'IDE_UNSPECIFIED', 'platform': 'PLATFORM_UNSPECIFIED', 'pluginType': 'GEMINI'},
                }).encode()
                req = urllib.request.Request(f'{base}:loadCodeAssist', data=load_body, headers=headers)
                with urllib.request.urlopen(req, timeout=10) as resp:
                    load_res = json.loads(resp.read())

                project_id = load_res.get('cloudaicompanionProject')
                if not project_id:
                    raise ValueError('No cloudaicompanionProject in loadCodeAssist response')

                quota_body = json.dumps({'project': project_id}).encode()
                req2 = urllib.request.Request(f'{base}:retrieveUserQuota', data=quota_body, headers=headers)
                with urllib.request.urlopen(req2, timeout=10) as resp2:
                    quota_res = json.loads(resp2.read())

                buckets = [b for b in quota_res.get('buckets', []) if not b.get('modelId', '').endswith('_vertex')]

                if buckets:
                    most_used = min(buckets, key=lambda b: b.get('remainingFraction', 1.0))
                    used_pct = round((1.0 - most_used.get('remainingFraction', 1.0)) * 100)
                    reset_time = most_used.get('resetTime')
                    primary_model = most_used.get('modelId', '')
                else:
                    used_pct = 0
                    reset_time = None
                    primary_model = ''

                result['gemini'] = {
                    'installed': True,
                    'authenticated': True,
                    'used_pct': used_pct,
                    'reset_time': reset_time,
                    'model': primary_model,
                    'buckets': [
                        {
                            'model': b.get('modelId', ''),
                            'used_pct': round((1.0 - b.get('remainingFraction', 1.0)) * 100),
                            'reset_time': b.get('resetTime'),
                        }
                        for b in buckets
                    ],
                }
                break

            except urllib.error.HTTPError as e:
                retry_count += 1
                body = read_http_error_body(e)
                if e.code == 401 and retry_count < max_retries and creds.get('refresh_token'):
                    success, new_creds, refresh_error = refresh_gemini_token(gemini_creds_path, creds)
                    if success:
                        creds = new_creds
                        continue
                    else:
                        last_error = {'fail_reason': 'auth_failed', 'error': refresh_error, 'http_code': 401}
                        if retry_count >= max_retries:
                            break
                        continue
                else:
                    last_error = classify_http_failure('gemini', e.code, body, context={'creds': creds})
                    break

            except Exception as e:
                retry_count += 1
                last_error = classify_exception_failure(e)
                if retry_count >= max_retries:
                    break

        if last_error:
            result['gemini'] = {
                'installed': True,
                'authenticated': last_error.get('fail_reason') not in ('auth_required', 'auth_failed'),
                'retry_count': retry_count,
                **last_error,
            }
        elif 'gemini' not in result:
            result['gemini'] = {
                'installed': True,
                'authenticated': False,
                'error': f'Failed after {retry_count} attempts',
                'fail_reason': 'unknown_error',
            }
    else:
        result['gemini'] = {'installed': False}


print(json.dumps(result))
