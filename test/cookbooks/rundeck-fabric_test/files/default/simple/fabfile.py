from fabric.api import task, local
from fabric.decorators import roles


def schedule(crontab):
    def annotate_function(func):
        setattr(func, 'schedule', crontab)
        return func
    return annotate_function


@roles('www')
@task
@schedule('30 * * * *')
def one():
    """Task one."""
    local('echo one')


@task
def two(arg1):
    """Task
    two."""
    local('echo two %s'%(arg1,))


@task
@roles('www')
@schedule('@monthly')
def three(c, d=1):
    """Take three."""
    local('echo three %s %s'%(c, d))
