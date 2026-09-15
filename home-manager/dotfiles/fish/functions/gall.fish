function gall --description "git: fetch all branches/remotes, then checkout or list"
    # https://stackoverflow.com/questions/10312521
    git fetch --all --prune
    if set -q argv[1]
        git checkout $argv[1]
    else
        git branch -a
    end
end
