#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["jinja2", "pyyaml", "typer"]
# ///
"""Write the root app for a test deployment of t11 into your own namespace.

The script fills apps-test.template.yaml and writes apps-test.local.yaml,
which git ignores. It asks for each value that no option gives, and offers
a default: press Enter to accept it. The defaults suit DLS.
"""

import getpass
import os
import re
from pathlib import Path
from typing import Annotated

import jinja2
import typer
import yaml

HERE = Path(__file__).resolve().parent
TEMPLATE = "apps-test.template.yaml"

HEADER = """\
# Root app for a test deployment of t11, written by make-apps-test.py
# from apps-test.template.yaml. Run the script again to change a value.
"""

# a Kubernetes namespace is a DNS-1123 label
DNS_LABEL = re.compile(r"[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?")
CLUSTER = re.compile(r"[-a-zA-Z0-9._]+")
GIT_URL = re.compile(r"[-a-zA-Z0-9._:/@~]+")
REVISION = re.compile(r"[-a-zA-Z0-9._/]+")
# the chart rejects a uid or gid that is not a positive integer
POSITIVE_INT = re.compile(r"[1-9][0-9]*")

app = typer.Typer(add_completion=False, pretty_exceptions_show_locals=False)


def ask(
    given: str | None,
    label: str,
    default: str,
    pattern: re.Pattern[str],
    yes: bool,
) -> str:
    """Return a value from its option, the user or its default.

    Args:
        given: the value from the command line, or None if the option is unset.
        label: the prompt text, also used in the error message.
        default: the value that Enter or --yes accepts.
        pattern: the full-match pattern that the value must satisfy. The
            patterns also keep quotes out of the quoted YAML strings.
        yes: accept the default without a prompt.

    Raises:
        typer.BadParameter: the value does not match pattern.
    """
    if given is not None:
        value = given
    elif yes:
        value = default
    else:
        value = typer.prompt(label, default=default)
    if not pattern.fullmatch(value):
        raise typer.BadParameter(f"{label}: '{value}' is not valid")
    return value


OUTPUT = HERE / "apps-test.local.yaml"


def value_option(help: str) -> typer.models.OptionInfo:
    """Return an option that defaults to None, so that the script asks for it."""
    return typer.Option(help=help, show_default=False)


@app.command(help=__doc__)
def main(
    namespace: Annotated[
        str | None,
        value_option("Namespace and Argo CD project (default: your username)"),
    ] = None,
    argocd_cluster: Annotated[
        str | None,
        value_option("Cluster where Argo CD creates the child apps (default: argus)"),
    ] = None,
    target_cluster: Annotated[
        str | None,
        value_option("Cluster for the t11 services (default: the Argo CD cluster)"),
    ] = None,
    services_repo: Annotated[
        str | None,
        value_option("t11-services repo, or your fork (default: t11-services)"),
    ] = None,
    revision: Annotated[
        str | None, value_option("t11-deployment revision (default: main)")
    ] = None,
    uid: Annotated[
        str | None, value_option("uid for the services (default: your uid)")
    ] = None,
    gid: Annotated[
        str | None, value_option("gid for the services (default: your gid)")
    ] = None,
    output: Annotated[
        Path, typer.Option("--output", "-o", help="File to write")
    ] = OUTPUT,
    yes: Annotated[
        bool,
        typer.Option("--yes", "-y", help="Accept every default, and overwrite OUTPUT"),
    ] = False,
) -> None:
    values = {}
    values["namespace"] = ask(namespace, "Namespace", getpass.getuser(), DNS_LABEL, yes)
    values["argocd_cluster"] = ask(
        argocd_cluster, "Argo CD cluster", "argus", CLUSTER, yes
    )
    values["target_cluster"] = ask(
        target_cluster, "Target cluster", values["argocd_cluster"], CLUSTER, yes
    )
    values["services_repo"] = ask(
        services_repo,
        "Services repo",
        "https://github.com/epics-containers/t11-services",
        GIT_URL,
        yes,
    )
    values["revision"] = ask(revision, "t11-deployment revision", "main", REVISION, yes)
    values["uid"] = ask(uid, "uid", str(os.getuid()), POSITIVE_INT, yes)
    values["gid"] = ask(gid, "gid", str(os.getgid()), POSITIVE_INT, yes)

    env = jinja2.Environment(
        loader=jinja2.FileSystemLoader(HERE),
        undefined=jinja2.StrictUndefined,
        keep_trailing_newline=True,
    )
    rendered = env.get_template(TEMPLATE).render(values)
    # replace the template's header comment with the output's own
    body = rendered[rendered.index("apiVersion:") :]
    text = HEADER + body
    # never write a file that Argo CD cannot read
    yaml.safe_load(text)

    if output.exists() and not yes:
        typer.confirm(f"{output} exists. Overwrite it?", abort=True)
    output.write_text(text)

    typer.echo(
        f"\nWrote {output}. To deploy, run:\n"
        f"  module load {values['argocd_cluster']}\n"
        f"  kubectl apply -n {values['namespace']} -f {output}\n"
        f"To tear down, run:\n"
        f"  kubectl delete -n {values['namespace']} application t11"
    )


if __name__ == "__main__":
    app()
