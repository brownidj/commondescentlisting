"""Verified HTTPS and credential-free diagnostics for paid refinement requests."""
import errno, http.client, socket, ssl, urllib.error


def tls_context():
    context = ssl.create_default_context()
    # Some macOS python.org installs do not populate OpenSSL's default CA file.
    # Add Mozilla's trusted bundle; never disable TLS/hostname verification.
    try:
        import certifi
    except ImportError:
        if not context.get_ca_certs():
            raise ValueError('No trusted TLS certificates. Install/configure a CA bundle in the preparation Python environment.')
    else:
        context.load_verify_locations(cafile=certifi.where())
    return context


def connection_problem(error, phase, client_id, request_id=None):
    reason = getattr(error, 'reason', None)
    cause = reason if isinstance(reason, BaseException) else error
    category = 'connection_error'
    explanation = 'Connection failed; no complete response received.'
    if isinstance(cause, ssl.SSLCertVerificationError):
        category = 'tls_certificate_error'
        explanation = 'TLS certificate verification failed: trusted issuer certificate unavailable or invalid.'
    elif isinstance(cause, (TimeoutError, socket.timeout)):
        category = 'timeout'
        explanation = 'The API connection or response timed out.'
    elif isinstance(cause, socket.gaierror):
        category = 'dns_error'
        explanation = 'The API hostname could not be resolved.'
    elif isinstance(cause, (ConnectionResetError, http.client.RemoteDisconnected)):
        category = 'connection_reset'
        explanation = 'The connection closed before a complete response was received.'
    elif isinstance(cause, http.client.IncompleteRead):
        category = 'incomplete_response'
        explanation = 'Only part of the API response was received.'
    elif isinstance(cause, ConnectionRefusedError):
        category = 'connection_refused'
        explanation = 'The API connection was refused.'
    elif isinstance(cause, ssl.SSLError):
        category = 'tls_error'
        explanation = 'The verified TLS connection failed.'
    return dict(category=category, explanation=explanation, exception_type=type(error).__name__,
                reason_type=type(cause).__name__, error_errno=getattr(cause, 'errno', None),
                tls_verify_code=getattr(cause, 'verify_code', None), phase=phase,
                client_request_id=client_id, request_id=request_id,
                # No raw exception/server message: these may contain request data.
                possible_billable_request=not (category in ('tls_certificate_error','dns_error','connection_refused') and phase=='connecting'))
