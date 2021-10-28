# Durin

-Durin is an interface that makes it easy to manage multiple projects using screen(terminal multiplexer).It is made to run/stop/view logs and update projects that depend on more than one project/service.

## Commands
| Command | Parameter | Description |
| ------ | ------ | ------ |
| start  | `<project>` \| `depends_off` | start project(s) with dependencies |
| stop  | `<project>`| stop project(s) |
| restart  | `<project>`| restart project(s) |
| update  | `<project>`| update project(s) |
| watch  | `<project>`| listen project(s) logs |
| remove-logs  | `<project>`| remove project(s) logs |
| show | - | lists of running project(s)|
| help | - | help |

> PS: `<project>` parameters is optinal all commands.
> If you want to run without needing dependencies, start with `dependcy_off` parameter.

## Configuration

| Parameter | Description |
| ------ | ------ |
| project_path | Full path of the projects you want to manage |
| log_folder | The full path of the folder where the log files of the projects will be created |
| dependency_map | The mapping list where you need to write the projects you can manage and their dependencies. The projects are separated by `:` |
| uncommitted_cmd | If there are changes committed in a project, if you are sure you want to update it, you should run the command to avoid a problem |
| uncommitted_cmd_msg | String to be printed after `uncommitted_cmd`  |
| update_project_cmd | List of commands to use when updating project(s) |
| start_project_cmd | The command to be used when starting projects is generally preferred to create a make file and `make run`|
| start_project_suffix_cmd | This is the command to be executed after `start_project_cmd`. `two commands are not piped together` |

### Example
> Let's assume that you have product/basket/order services in an e-commerce project. If you need product service while developing the basket project, you can do this without the need for any virtualization. Let's start by creating the configuration.

For the above example, let's create the config.yaml as follows.

```sh
project_path: /Users/ree/go/src/github.com/ecommerce
log_folder: /tmp/ecommerce.log

dependency_map:
  - "product"
  - "basket:product"
  - "order:product:basket"

uncommitted_cmd: "git stash"
uncommitted_cmd_msg: "[*] existing changes are stashed"

update_project_cmd:
  - "echo '[*] git pull origin master'"
  - "git checkout master"
  - "git pull origin master"

start_project_cmd: "cd $project_path; make run"
start_project_suffix_cmd: "2>&1 | tee -a $LOG_FOLDER/$project.log"
```


#### Management Example
```sh
~$ service-runner.sh start basket
[*] product is running.
[*] basket is running.
~$ service-runner.sh show
product is running.
basket is running.
~$ service-runner.sh stop basket
[*] basket is stopping.
~$ service-runner.sh show
product is running.
~$ service-runner.sh stop product
[*] product is stopping
~$ service-runner.sh start basket depends_off
[*] basket is running.
~$ service-runner.sh show
basket is running.
~$ service-runner.sh stop
product is not running
[*] basket is stopping
order is not running
~$ # Happy Bash Days;
```
