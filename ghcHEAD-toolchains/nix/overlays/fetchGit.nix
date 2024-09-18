self: super: {
  # This provides an API similar to `pkgs.fetchgit` except that this uses
  # builtins.fetchGit under the hood.  You can override `fetchgit` with
  # `fetchGit` in circumstances where you want to fetch private repositories.
  # We don't override `fetchgit` globally, though, to avoid disturbing the
  # hash for upstream builds.
  fetchGit = {
    url,
    name ? null,
    rev ? "HEAD",
    branchName ? null,
    fetchSubmodules ? true,
    deepClone ? false,
    ...
  }:
    builtins.fetchGit {
      inherit url rev;

      ${
        if name == null
        then null
        else "name"
      } =
        name;

      ${
        if branchName == null
        then null
        else "ref"
      } =
        branchName;

      submodules = fetchSubmodules;

      shallow = !deepClone;

      allRefs = deepClone;
    };
}
