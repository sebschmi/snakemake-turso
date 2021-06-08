# Snakemake template for turso

This is a Snakemake project template that can be executed on the turso federation (ukk02/vorna/...).

## Setup

First install a `conda` implementation: `anaconda`, `miniconda` or `mamba`.
Since anaconda and miniconda are notoriously slow at times, I would recommend [`mamba`](https://github.com/conda-forge/miniforge#mambaforge).

Now you should rename the environment in the `environment.yml` to something that fits your project.

Then you can create the conda environment for your project using by executing the following:
```shell
mamba create -f environment.yml
```

And activate the environment (note that as of now, even with mamba you likely have to use `conda activate`):
```shell
conda activate <your-environment-name>
```

## Programming

Take a look at the template `Snakefile`.
Basically, whenever you want a rule to be executed on the login node, you specify it as `localrule`.
Keep in mind that on the login node, only light computations should be performed, like e.g. compiles or downloads.
Downloads are only possible on the login node, as the other nodes do not have a connection to the internet.

If you want to execute a rule on the cluster, you specify it as `rule`, and you need to add a `resources` section. Take a look at the `bcalm2` rule in the `Snakefile` for an example.
