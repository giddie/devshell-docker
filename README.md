# Usage

I create a `.local` directory in the project I'm working on, and copy this
template into `.local/devshell`. Then I create a `.local/bin` directory and add
it to my path with a `.envrc` file (see [direnv](https://direnv.net/)). I
add a symlink to the `.local/devshell/devshell` script there.

```
.envrc
.local
├── bin
│   ├── devshell -> ../devshell/devshell
│   ├── ds -> devshell
└── devshell
    ├── devshell
    └── ...
```

Then I run commands like this:

```
# ds echo hello world
hello world
```
