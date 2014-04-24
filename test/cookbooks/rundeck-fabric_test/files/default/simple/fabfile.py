from fabric.api import task, run
from fabric.decorators import roles

@roles('live')
@task
def one():
    """Task one."""
    run('date')


@task
def two(arg1):
    """Task
    two."""
    run('date')

@task
@roles('live')
def three(c, d=1):
    """Take three."""
    run('date')
