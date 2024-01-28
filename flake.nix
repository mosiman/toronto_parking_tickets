{
  description = "Toronto Parking Ticket Data";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, flake-utils }: 
    flake-utils.lib.eachDefaultSystem (system:
      let 
        pkgs = import nixpkgs { inherit system; };
      in
      {
         devShell = pkgs.mkShell {
           buildInputs = [
             pkgs.go
             pkgs.python3
             pkgs.duckdb
             pkgs.docker
             pkgs.poetry
             pkgs.libpostal

             # Python stuff
             pkgs.python311Packages.pandas
             pkgs.python311Packages.numpy
             pkgs.python311Packages.scikit-learn
             pkgs.python311Packages.matplotlib
             pkgs.python311Packages.duckdb
             pkgs.python311Packages.psycopg
             pkgs.python311Packages.requests
             pkgs.python311Packages.tqdm
             pkgs.python311Packages.python-lsp-server
           ];
         };
      });
}
