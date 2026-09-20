# Sphinx configuration for the t11-deployment documentation site.
# Docs-only build: there is no Python package to autodoc.
#
# Build locally from the repo root:
#   uv run --with-requirements docs/requirements.txt \
#     sphinx-build -b html -W --keep-going docs docs/_build/html

# -- Project information -----------------------------------------------------
project = "t11-deployment"
author = "Giles Knap"
html_title = "t11-deployment"

# -- General configuration ---------------------------------------------------
extensions = [
    "myst_parser",
    "sphinx_design",
    "sphinx_copybutton",
    "sphinxcontrib.mermaid",
]

master_doc = "index"
exclude_patterns = ["_build", "Thumbs.db", ".DS_Store", "_snippets/*"]

# Don't fail the build on missing cross-references.
nitpicky = False

# -- MyST configuration ------------------------------------------------------
myst_enable_extensions = [
    "colon_fence",
    "deflist",
    "substitution",
    "attrs_inline",
]
myst_heading_anchors = 3

# -- HTML output -------------------------------------------------------------
html_theme = "pydata_sphinx_theme"
html_static_path = ["_static"]
html_css_files = ["custom.css"]
html_show_sphinx = False
html_logo = "_static/epics-containers.png"
html_favicon = "_static/epics-containers.png"

html_theme_options = {
    "github_url": "https://github.com/epics-containers/t11-deployment",
    "use_edit_page_button": True,
    "navigation_with_keys": False,
    "icon_links": [],
    "logo": {
        "text": "t11-deployment",
        "alt_text": "epics-containers — t11 home",
    },
    "navbar_end": ["theme-switcher", "navbar-icon-links"],
}

# Wires up the "edit this page" button.
html_context = {
    "github_user": "epics-containers",
    "github_repo": "t11-deployment",
    "github_version": "main",
    "doc_path": "docs",
}

# -- sphinx-copybutton -------------------------------------------------------
# Strip common interactive prompts so copied snippets are runnable.
copybutton_prompt_text = r">>> |\.\.\. |\$ |# "
copybutton_prompt_is_regexp = True

# -- sphinxcontrib-mermaid ---------------------------------------------------
# 11.6+ fixes the subgraph-title / nested-box overlap seen in 11.4.x.
mermaid_version = "11.15.0"
