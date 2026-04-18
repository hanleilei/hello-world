"""
Lambda entry-point adapter for our Terraform-managed API Gateway.

Chalice routes requests using event['resource'] (the API Gateway resource
template, e.g. '/health').  Our Terraform API Gateway uses a single catch-all
proxy resource '/{proxy+}', which means every request — regardless of the
actual URL path — arrives with resource='/{proxy+}'.  Chalice cannot match
that against any registered @app.route(), so it falls back to returning 405.

This thin adapter rewrites resource to the actual request path before handing
the event to Chalice, restoring correct routing without any changes to app.py
or the API Gateway Terraform config.
"""

from app import app


def api_handler(event, context):
    if event.get("resource") == "/{proxy+}":
        event = dict(event, resource=event.get("path", ""))
    return app(event, context)
