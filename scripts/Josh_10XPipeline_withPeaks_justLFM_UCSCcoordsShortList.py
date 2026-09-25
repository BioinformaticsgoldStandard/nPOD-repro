#!/usr/bin/env python3

import os
import sys
import gzip
import argparse
import logging
import subprocess
import pysam
import numpy as np
import pandas as pd
import scipy.sparse
from multiprocessing import Pool

def generate_matrix(args):
	tagalign_file = args.tag
	pass_barcodes = open(args.keep).read().splitlines()

	lf_mtx_file = args.output_prefix + '.long_fmt_mtx.txt.gz'
	barcodes_file = args.output_prefix + '.barcodes'
	regions_file = args.output_prefix + '.regions'
	mtx_file = args.output_prefix + '.mtx'

	# Portability fix (repro branch): path was previously hardcoded as a string literal
	# inside this function body, making it impossible to override without editing the
	# source.  Moved to --windows-file CLI argument; original path kept as the default
	# so existing callers that relied on the container mounting the file there still work.
	windows_file = args.windows_file
	window_intersect = intersect_regions(tagalign_file, windows_file)
	cut = subprocess.Popen(['cut', '-f', '4,10'], stdin=window_intersect.stdout, stdout=subprocess.PIPE)
	sort = subprocess.Popen(['sort', '-S', '{}G'.format(args.memory * args.threads)], stdin=cut.stdout, stdout=subprocess.PIPE)
	uniq = subprocess.Popen(['uniq', '-c'], stdin=sort.stdout, stdout=subprocess.PIPE)
	awk = subprocess.Popen(['awk', '''BEGIN{{OFS="\\t"}} {{print $2,$3,$1}}'''], stdin=uniq.stdout, stdout=subprocess.PIPE)
	with gzip.open(lf_mtx_file, 'wt') as f:
		subprocess.call(['gzip', '-c'], stdin=awk.stdout, stdout=f)

	lf_mtx = pd.read_table(lf_mtx_file, sep='\t', header=None, names=['barcode','region','count'])
	lf_mtx = lf_mtx.loc[lf_mtx['barcode'].isin(pass_barcodes)]
	lf_mtx.to_csv(lf_mtx_file, sep='\t', header=False, index=False, compression='gzip')
	return

def intersect_regions(tagalign, regions):
	awk_cmd = ['awk', '''BEGIN{{FS=OFS="\\t"}} {{peakid=$1":"$2"-"$3; gsub("chr","",peakid); print $1, $2, $3, peakid}}''', regions]
	intersect_cmd = ['bedtools', 'intersect', '-a', tagalign, '-b', '-', '-wa', '-wb']
	awk = subprocess.Popen(awk_cmd, stdout=subprocess.PIPE)
	intersect = subprocess.Popen(intersect_cmd, stdin=awk.stdout, stdout=subprocess.PIPE)
	return intersect

def make_windows(args):
	makewindows_cmd = ['bedtools', 'makewindows', '-g', args.chrom_sizes, '-w', str(args.window_size * 1000)]
	filter_cmd = ['grep', '-v', '_']
	blacklist_cmd = ['bedtools', 'intersect', '-a', '-', '-b', args.blacklist_file, '-v']
	windows_file = '{}.{}kb_windows.bed'.format(args.output_prefix, args.window_size)
	with open(windows_file, 'w') as f:
		makewindows = subprocess.Popen(makewindows_cmd, stdout=subprocess.PIPE)
		filt = subprocess.Popen(filter_cmd, stdin=makewindows.stdout, stdout=subprocess.PIPE)
		subprocess.call(blacklist_cmd, stdin=filt.stdout, stdout=f)
	return windows_file

def main(args):
	logging.info('Start.')
	if not os.path.isdir(args.output):
		os.makedirs(args.output)
	args.output_prefix = os.path.join(args.output, args.name)
	if not args.skip_matrix:
		logging.info('Generating tagalign and chromatin accessibility matrix.')
		generate_matrix(args)
	logging.info('Finish.')
	return

def process_args():
	parser = argparse.ArgumentParser(description='Use 10X output to process snATAC-seq data.')
	io_group = parser.add_argument_group('I/O arguments')
	#io_group.add_argument('-b', '--input-bam', required=True, type=str, help='Position sorted bam from 10X output')
	io_group.add_argument('-o', '--output', required=True, type=str, default=os.getcwd(), help='Output directory to store processed files')
	io_group.add_argument('-n', '--name', required=True, type=str, help='Prefix for naming all output files')
	io_group.add_argument('-k', '--keep', required=True, type=str, help='List of barcodes to keep')
	io_group.add_argument('-a', '--tag', required=True, type=str, help='Path to tagAlign.gz file')

	align_group = parser.add_argument_group('Alignment arguments')
	align_group.add_argument('-t', '--threads', required=False, type=int, default=8, help='Number of threads to use for alignment [8]')
	align_group.add_argument('-m', '--memory', required=False, type=int, default=4, help='Maximum amount of memory (G) per thread for samtools sort [4]')
	align_group.add_argument('-q', '--map-quality', required=False, type=int, default=30, help='Mapping quality score filter for samtools [30]')
	align_group.add_argument('-ref', '--reference', required=False, type=str, default='/nfs/lab/elisha/nPOD_output/scripts/references/hg38.fa', help='Path to the reference genome')

	dup_group = parser.add_argument_group('Remove duplicates arguments')
	dup_group.add_argument('--picard', required=False, type=str, default='/home/joshchiou/bin/picard.jar', help='Path to picard.jar')

	matrix_group = parser.add_argument_group('Matrix generation arguments')
	matrix_group.add_argument('--shift', required=False, type=int, default=-100, help='Read shift length')
	matrix_group.add_argument('--extsize', required=False, type=int, default=200, help='Read extension size')
	matrix_group.add_argument('--minimum-reads', required=False, type=int, default=500, help='Minimum number of reads for barcode inclusion')
	matrix_group.add_argument('--minimum-frip', required=False, type=float, default=0, help='Minimum frip for barcode inclusion')
	matrix_group.add_argument('--window-size', required=False, type=int, default=5, help='Size (kb) to use for defining windows of accessibility')
	matrix_group.add_argument('--chrom-sizes', required=False, type=str, default='/reference_files/hg38.chrom.sizes', help='Chromosome sizes file from UCSC')
	matrix_group.add_argument('--blacklist-file', required=False, type=str, default='/reference_files/hg38-blacklist.v3.bed', help='BED file of blacklisted regions')
	matrix_group.add_argument('--promoter-file', required=False, type=str, default='/reference_files/gencode.hg38.v19.2kb_autosomal_prom_uniq.bed', help='BED file of autosomal promoter regions')
	matrix_group.add_argument('--windows-file', required=False, type=str, default='/reference_files/jan17_2kbUpstream_hg38Promoters_gencode_v41_UCSCcoors_mod.txt', help='BED file of promoter windows used for accessibility matrix (portability fix: was hardcoded in function body)')


	skip_group = parser.add_argument_group('Skip steps')
	skip_group.add_argument('--skip-convert', required=False, action='store_true', default=False, help='Skip bam conversion step')
	skip_group.add_argument('--skip-rmdup', required=False, action='store_true', default=False, help='Skip duplicate removal step')
	skip_group.add_argument('--skip-qc', required=False, action='store_true', default=False, help='Skip quality metrics step')
	skip_group.add_argument('--skip-matrix', required=False, action='store_true', default=False, help='Skip matrix generation step')
	return parser.parse_args()

if __name__ == '__main__':
	logging.basicConfig(format='[%(filename)s] %(asctime)s %(levelname)s: %(message)s', datefmt='%I:%M:%S', level=logging.INFO)
	args = process_args()
	main(args)
