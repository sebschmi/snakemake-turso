import itertools, sys, traceback, pathlib, os

###############################
###### Preprocess Config ######
###############################

print("Preprocessing config", flush = True)

# Some standard directories
# If you have a lot of data, you can change this to a larger partition.
# Keep in mind though that the $WRKDIR on turso is very fragile and you will likely shoot down the whole cluster if you do not read and understand this first:
# https://wiki.helsinki.fi/display/it4sci/Lustre+User+Guide#LustreUserGuide-4.1FileLockinginLustreisnotanadvisorytobeignored
DATADIR = "data/"
if "datadir" in config:
    DATADIR = config["datadir"]
DATADIR = os.path.abspath(DATADIR)

# If you have separate executables you can store them here.
PROGRAMDIR = "data/program"
if "programdir" in config:
    PROGRAMDIR = config["programdir"]
PROGRAMDIR = os.path.abspath(PROGRAMDIR)

# You can have a separate dir to store the plots/tables generated by your experiments.
REPORTDIR = "data/reports/"
if "reportdir" in config:
    REPORTDIR = config["reportdir"]
REPORTDIR = os.path.abspath(REPORTDIR)

print("DATADIR: {}".format(DATADIR))
print("PROGRAMDIR: {}".format(PROGRAMDIR))
print("REPORTDIR: {}".format(REPORTDIR))

# This is the maximum number of cores for your default ukko2 machine. Vorna machines have 32.
MAX_THREADS = 56
print("Setting MAX_THREADS to " + str(MAX_THREADS), flush = True)

# If you have source code in your repository, you can make snakemake compile it automatically on change by collecting all the source files.
# This is for Rust code, you can apply it to your programming language of choice.
# rust_sources = list(map(str, itertools.chain(pathlib.Path('implementation').glob('**/Cargo.toml'), pathlib.Path('implementation').glob('**/*.rs'))))

# In case you want to access the current date.
import datetime
today = datetime.date.today().isoformat()

print("Finished config preprocessing", flush = True)

############################
###### File Constants ######
############################

# I like to have global constants for most involved file patterns to prevent typos.
# I keep single letter abreviations in front of the wildcards to make the resulting paths more readable.
# Helps especially when there are many arguments.
READS_SRA = os.path.join(DATADIR, "reads", "s{species}", "sra", "reads.sra")
READS_FASTA = os.path.join(DATADIR, "reads", "s{species}", "fasta", "reads.fa")
ASSEMBLY_SOURCE_READS = os.path.join(DATADIR, "assembly", "s{species}-k{k}", "reads.fa")
ASSEMBLY = os.path.join(DATADIR, "assembly", "s{species}-k{k}", "assembly.fa")
REPORT = os.path.join(REPORTDIR, "s{species}-k{k}", "report.txt")

#################################
###### Global report rules ######
#################################

# By default, snakemake executes the first rule if no target is given.
# If you don't like that, this rule makes it do nothing if no target is given.
localrules: do_nothing
rule do_nothing:
    shell:  "echo 'No target specified'"

# Here can be rules that specify a set of reports you would like to create, like e.g. all executions for all combinations of different k values and species.
localrules: report_all
rule report_all:
    input:  reports = expand(REPORT, species = ["ecoli", "scerevisiae"], k = [23, 31, 39]),

###############################
###### Report Generation ######
###############################

# Here can be rules to generate reports from your experiments, like e.g. plots or tables.
localrules: create_single_report
rule create_single_report:
    input:  assembly = ASSEMBLY,
    output: report = REPORT,
    conda:  "config/conda-biopython-env.yml"
    script: "scripts/create_single_report.py"

########################
###### Assembly ########
########################

# These sections depend heavily on your workflow, for our example we have a section for genome assemblers here.

# This is an example for a rule that can be executed on a cluster.
# Note that for a more dynamic allocation of resources, you can use functions to determine the resources (as you can do with inputs, outputs, logs, params, etc...), e.g.
# queue = lambda wildcards: "long" if wildcards.species == "human" else "short",
# or
# queue = determine_queue_based_on_wildcards,
# where determine_queue_based_on_wildcards is a function that takes a single argument 'wildcards' and returns a string.
rule bcalm2:
    input:  reads = ASSEMBLY_SOURCE_READS,
    output: assembly = ASSEMBLY,
    conda:  "config/conda-bcalm2-env.yml",
    params:
    # The maximum number of threads usable by your rule. I am not sure if this is needed, since it is always the same as resources.cpus.
    threads: MAX_THREADS,
               # The amount of RAM your job needs at max. If your job requests more at any time, it will be killed.
    resources: mem_mb = 2000,
               # The time slice that should be allocated to your job. If your job runs longer than this, it will be killed.
               time_min = 60,
               # The number of cores your job needs.
               cpus = MAX_THREADS,
               # The federation queue your job should be placed in. This depends on which cluster you use, but at least vorna and ukko2 both have a "short" queue.
               queue = "short",
    shell:  """
        bcalm -nb-cores {threads} -in {input.reads} -out {output.assembly} -kmer-size {wildcards.k} -abundance-min 2
        mv '{output.assembly}.unitigs.fa' '{output.assembly}'
    """

#######################
###### Downloads ######
#######################

# Here can be rules to download your input files.
# These must be localrules, as the compute nodes of the federated cluster do not have a connection to the internet.

def get_reads_url(wildcards):
    # Snakemake just swallows whatever errors happen in functions.
    # The only way around that is to handle and print the error ourselves.
    try:
        species = wildcards.species

        if species == "ecoli":
            return "https://sra-downloadb.be-md.ncbi.nlm.nih.gov/sos3/sra-pub-run-20/SRR12793243/SRR12793243.1"
        elif species == "scerevisiae":
            return "https://sra-download.ncbi.nlm.nih.gov/traces/sra78/SRR/014398/SRR14744387"
        else:
            raise Exception("Unknown species: {}".format(species))
    except Exception:
        traceback.print_exc()
        sys.exit("Catched exception")

localrules: download_sra_file
rule download_sra_file:
    output: file = READS_SRA,
    params: url = get_reads_url,
    shell:  """
        wget --progress=dot:mega -O '{output.file}' '{params.url}'
    """

rule convert_sra_download:
    input:  file = READS_SRA,
    output: file = READS_FASTA,
    conda:  "config/conda-convert-reads-env.yml"
    shell:  "fastq-dump --stdout --fasta default '{input.file}' > '{output.file}'"

# I link the reads to each assembly directory separately, such that bcalm creates its auxiliary files in that directory instead of the download directory.
localrules: download_reads
rule download_reads:
    input:  file = READS_FASTA,
    output: file = ASSEMBLY_SOURCE_READS,
    shell:  "ln -sr -T '{input.file}' '{output.file}'"

##############################
###### Download results ######
##############################

# Here is a template for a rule to download report files from turso to your local machine.
# You can use something similar, just make sure to update the paths and the include specification.
#localrules: sync_turso_results
#rule sync_turso_results:
#    conda: "config/conda-rsync-env.yml"
#    shell: """
#        mkdir -p data/reports
#        rsync --verbose --recursive --no-relative --include="*/" --include="report.pdf" --include="aggregated-report.pdf" --exclude="*" turso:'/proj/sebschmi/git/practical-omnitigs/data/reports/' data/reports
#        """

