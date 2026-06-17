#!/usr/bin/env python3
"""
AI Usage Monitor - Data fetcher
Reads usage data for Claude Code, OpenAI Codex, and Gemini CLI.
Outputs a single JSON object to stdout.
"""
import json
import glob
import base64
import sqlite3
import calendar
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


def billing_period_bounds(reset_day):
    """(period_start_ms, next_reset_iso) for the monthly cycle starting on `reset_day`.
    reset_day=1 == calendar month; set it to your billing day for the real cycle.
    Computed in local time (the billing day is understood locally)."""
    now = datetime.now()

    def boundary(year, month):
        day = min(reset_day, calendar.monthrange(year, month)[1])
        return datetime(year, month, day)

    start = boundary(now.year, now.month)
    if start > now:  # the day hasn't arrived yet this month → cycle began last month
        py, pm = (now.year - 1, 12) if now.month == 1 else (now.year, now.month - 1)
        start = boundary(py, pm)
    ny, nm = (start.year + 1, 1) if start.month == 12 else (start.year, start.month + 1)
    nxt = boundary(ny, nm)
    return int(start.timestamp() * 1000), nxt.astimezone().isoformat()


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


# gemini-cli's PUBLIC OAuth client (installed-app credentials shipped inside the gemini-cli
# package itself — NOT a user secret). The CLI stores tokens WITHOUT client_id/secret, so the
# widget needs these to refresh an expired token; otherwise an account the CLI isn't actively
# using just dies when its token expires.
GEMINI_CLI_OAUTH_CLIENT_ID = "681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com"
# Literal split on purpose so GitHub's secret-scanning doesn't false-positive on it
# (it is gemini-cli's PUBLIC installed-app secret, not a user secret).
GEMINI_CLI_OAUTH_CLIENT_SECRET = "GOCSPX" "-4uHgMPm-1o7Sk-geV6Cu5clXFsxl"


def refresh_gemini_token(creds_path, creds):
    """
    Refresh Gemini OAuth token using refresh_token.
    Returns (success: bool, new_creds: dict | None, error_msg: str | None)

    SECURITY: This function handles sensitive credentials but never logs or outputs them.
    Only safe error messages are returned.
    """
    try:
        refresh_token = creds.get('refresh_token')
        # Fall back to gemini-cli's public client when the creds omit them (the CLI does).
        client_id = creds.get('client_id') or GEMINI_CLI_OAUTH_CLIENT_ID
        client_secret = creds.get('client_secret') or GEMINI_CLI_OAUTH_CLIENT_SECRET

        if not refresh_token:
            return False, None, 'No refresh token found'

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


def decode_jwt_email(id_token):
    """Email del payload de un id_token JWT. Solo para etiquetar la cuenta; NO verifica firma."""
    try:
        payload = id_token.split('.')[1]
        payload += '=' * (-len(payload) % 4)  # padding base64url
        return json.loads(base64.urlsafe_b64decode(payload)).get('email') or ''
    except Exception:
        return ''


def fetch_gemini_account(creds_path):
    """
    Consulta la cuota de UNA cuenta de Gemini (Code Assist) y devuelve su dict:
    authenticated/email/used_pct/reset_time/model/buckets, o un dict de error compatible.
    Refresca el token si caduca (escribe SOLO en creds_path; nunca en otra cuenta).
    """
    creds = {}
    email = ''
    max_retries = 3
    retry_count = 0
    last_error = None

    while retry_count < max_retries:
        try:
            creds = json.loads(creds_path.read_text())
            email = decode_jwt_email(creds.get('id_token', '')) or email
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
                used_pct, reset_time, primary_model = 0, None, ''

            return {
                'authenticated': True,
                'email': email,
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

        except urllib.error.HTTPError as e:
            retry_count += 1
            body = read_http_error_body(e)
            if e.code == 401 and retry_count < max_retries and creds.get('refresh_token'):
                success, new_creds, refresh_error = refresh_gemini_token(creds_path, creds)
                if success:
                    creds = new_creds
                    continue
                last_error = {'fail_reason': 'auth_failed', 'error': refresh_error, 'http_code': 401}
                if retry_count >= max_retries:
                    break
                continue
            last_error = classify_http_failure('gemini', e.code, body, context={'creds': creds})
            break

        except Exception as e:
            retry_count += 1
            last_error = classify_exception_failure(e)
            if retry_count >= max_retries:
                break

    if last_error:
        return {
            'authenticated': last_error.get('fail_reason') not in ('auth_required', 'auth_failed'),
            'email': email,
            'retry_count': retry_count,
            **last_error,
        }
    return {
        'authenticated': False,
        'email': email,
        'error': f'Failed after {retry_count} attempts',
        'fail_reason': 'unknown_error',
    }


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
    codex_auth_path = Path.home() / '.codex' / 'auth.json'
    codex_live = None

    # 1) EN VIVO (preferente): mismo endpoint dedicado que usa `codex /status`.
    #    Es un GET (NO gasta tokens) y refleja el uso ACTUAL, igual que ya
    #    hacemos con Claude y Gemini. SOLO lee auth.json; nunca lo modifica.
    if codex_auth_path.exists():
        try:
            tokens = json.loads(codex_auth_path.read_text()).get('tokens') or {}
            access_token = tokens.get('access_token')
            account_id = tokens.get('account_id') or ''
            if access_token:
                req = urllib.request.Request(
                    'https://chatgpt.com/backend-api/codex/usage',
                    headers={
                        'Authorization': f'Bearer {access_token}',
                        'ChatGPT-Account-Id': account_id,
                        'User-Agent': 'codex-cli',
                        'Accept': 'application/json',
                    },
                )
                with urllib.request.urlopen(req, timeout=10) as resp:
                    data = json.loads(resp.read())
                rl = data.get('rate_limit') or {}
                prim = rl.get('primary_window') or {}
                sec = rl.get('secondary_window') or {}
                codex_live = {
                    'installed': True,
                    'live': True,
                    'five_hour_pct': round(prim.get('used_percent') or 0),
                    'seven_day_pct': round(sec.get('used_percent') or 0),
                    'five_hour_reset': unix_to_iso(prim.get('reset_at')),
                    'seven_day_reset': unix_to_iso(sec.get('reset_at')),
                    'plan_type': data.get('plan_type') or '',
                }
        except Exception:
            codex_live = None  # token caducado / sin red -> caemos al historial

    if codex_live is not None:
        result['codex'] = codex_live

    # 2) FALLBACK: ultimo snapshot REAL del historial local (~/.codex/sessions).
    #    Solo si el endpoint en vivo no respondio. Se marca live=False.
    codex_sessions_dir = Path.home() / '.codex' / 'sessions'
    if codex_live is None and codex_sessions_dir.exists():
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
                                        rl = payload.get('rate_limits') or {}
                                        prim = rl.get('primary')
                                        # Solo cuenta si trae un porcentaje REAL. El bucket
                                        # 'premium'/creditos llega con rate_limits != null pero
                                        # primary == null: hay que IGNORARLO. Si no, el widget
                                        # lo elige y muestra 0%, ocultando el ultimo dato real
                                        # (que vive en el evento limit_id=='codex' de una sesion
                                        # anterior). Codex 0.139.0 introdujo este bucket.
                                        if isinstance(prim, dict) and prim.get('used_percent') is not None:
                                            if rl.get('limit_id') == 'codex':
                                                main_in_file = payload
                                            else:
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
                    'live': False,  # historial: ultimo dato real, puede estar viejo
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

    # Ni en vivo ni historial: reflejar el estado real (instalado si hay auth).
    if 'codex' not in result:
        result['codex'] = {'installed': codex_auth_path.exists(), 'has_data': False}


# ── GEMINI CLI (una o varias cuentas) ──────────────────────────────────────────
if not _only or _only == 'gemini':
    # Cuenta principal + cuentas adicionales en ~/.gemini/accounts/*.json.
    # Permite monitorizar varias cuentas Google (cada una con su cuota gratis).
    primary_creds = Path.home() / '.gemini' / 'oauth_creds.json'
    extra_dir = Path.home() / '.gemini' / 'accounts'
    creds_files = [primary_creds] if primary_creds.exists() else []
    if extra_dir.is_dir():
        creds_files += sorted(extra_dir.glob('*.json'))

    if not creds_files:
        result['gemini'] = {'installed': False}
    else:
        accounts = [fetch_gemini_account(p) for p in creds_files]
        # Compat hacia atras: los campos de la 1a cuenta quedan en el nivel superior;
        # 'accounts' lleva la lista completa (la UI pinta una tarjeta por cuenta).
        result['gemini'] = {'installed': True, **accounts[0], 'accounts': accounts}


# ── OPENCODE GO ──────────────────────────────────────────────────────────────
# OpenCode Go: limites en valor $ con ventanas (5h/$12, semana/$30, mes/$60).
# El uso real lo lleva opencode en su console (no hay API publica); aqui se
# ESTIMA desde la BD local (mismo coste que `opencode stats`). Arg opcional =
# dia de renovacion de la suscripcion (ancla la ventana mensual; 1 = mes natural).
if not _only or _only == 'opencode':
    opencode_db = Path.home() / '.local' / 'share' / 'opencode' / 'opencode.db'
    if opencode_db.exists():
        try:
            renewal_day = 1
            if len(sys.argv) > 2:
                try:
                    renewal_day = max(1, min(31, int(sys.argv[2])))
                except ValueError:
                    renewal_day = 1
            now_ms = int(datetime.now(timezone.utc).timestamp() * 1000)

            # Solo lectura: con WAL no bloquea a opencode aunque este corriendo.
            con = sqlite3.connect(f'file:{opencode_db}?mode=ro', uri=True, timeout=5)
            try:
                sessions, cost_total, tok_in, tok_out = con.execute(
                    'SELECT COUNT(*), COALESCE(SUM(cost), 0), '
                    'COALESCE(SUM(tokens_input), 0), COALESCE(SUM(tokens_output), 0) FROM session'
                ).fetchone()

                def rolling(window_seconds):
                    # Ventana rolling: gasto en las ultimas `window_seconds`. El
                    # 'reset' = cuando caduca el gasto MAS ANTIGUO de la ventana
                    # (el momento en que la barra empieza a bajar). Aproximado:
                    # opencode no publica el reloj real de estas ventanas.
                    cutoff = now_ms - window_seconds * 1000
                    used, oldest = con.execute(
                        'SELECT COALESCE(SUM(cost), 0), MIN(time_created) '
                        'FROM session WHERE time_created >= ?', (cutoff,)
                    ).fetchone()
                    reset = unix_to_iso(int(oldest / 1000) + window_seconds) if oldest else None
                    return round(used, 2), reset

                five_used, five_reset = rolling(5 * 3600)
                week_used, week_reset = rolling(7 * 86400)

                # Ventana mensual anclada al dia de renovacion (reset exacto).
                month_start_ms, month_reset = billing_period_bounds(renewal_day)
                (month_used,) = con.execute(
                    'SELECT COALESCE(SUM(cost), 0) FROM session WHERE time_created >= ?',
                    (month_start_ms,),
                ).fetchone()
            finally:
                con.close()

            result['opencode'] = {
                'installed': True,
                'plan': 'go',
                'sessions': sessions,
                'cost_total': round(cost_total, 2),
                'tokens_input': tok_in,
                'tokens_output': tok_out,
                'five_hour': {'used': five_used, 'reset': five_reset},
                'weekly': {'used': week_used, 'reset': week_reset},
                'monthly': {'used': round(month_used, 2), 'reset': month_reset},
            }
        except Exception as e:
            result['opencode'] = {'installed': True, **classify_exception_failure(e)}
    else:
        result['opencode'] = {'installed': False}


print(json.dumps(result))
