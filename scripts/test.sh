#!/bin/bash
set -xeuo pipefail

GENOME=smallGRCh37
PROFILE=singularity
SAMPLE=data/tsv/tiny.tsv
TAG=1.2.3
TEST=ALL
TRAVIS=${TRAVIS:-false}

while [[ $# -gt 0 ]]
do
  key=$1
  case $key in
    -g|--genome)
    GENOME=$2
    shift # past argument
    shift # past value
    ;;
    -p|--profile)
    PROFILE=$2
    shift # past argument
    shift # past value
    ;;
    -s|--sample)
    SAMPLE=$2
    shift # past argument
    shift # past value
    ;;
    -t|--test)
    TEST=$2
    shift # past argument
    shift # past value
    ;;
    --tag)
    TAG=$2
    shift # past argument
    shift # past value
    ;;
    *) # unknown option
    shift # past argument
    ;;
  esac
done

function nf_test() {
  echo "$(tput setaf 1)nextflow run $@ -profile $PROFILE --genome $GENOME -resume --verbose$(tput sgr0)"
  nextflow run $@ -profile $PROFILE --genome $GENOME -resume --verbose
}

# Build references only for smallGRCh37
if [[ $GENOME == smallGRCh37 ]] && [[ $TEST != BUILDCONTAINERS ]]
then
  nf_test buildReferences.nf --download
  # Remove images only on TRAVIS
  if [[ $PROFILE == docker ]] && [[ $TRAVIS == true ]]
  then
    docker rmi -f maxulysse/igvtools:${TAG}
  elif [[ $PROFILE == singularity ]] && [[ $TRAVIS == true ]]
  then
    rm -rf work/singularity/igvtools-${TAG}.img
  fi
fi

if [[ $TEST = MAPPING ]]
then
  nf_test . --step mapping --sample $SAMPLE
fi

if [[ $TEST = REALIGN ]] || [[ $TEST = ALL ]]
then
  nf_test . --step mapping --sample $SAMPLE
  nf_test . --step realign --noReports
  nf_test . --step realign --tools HaplotypeCaller
  nf_test . --step realign --tools HaplotypeCaller --noReports --noGVCF
fi

if [[ $TEST = RECALIBRATE ]] || [[ $TEST = ALL ]]
then
  nf_test . --step mapping --sample $SAMPLE
  nf_test . --step recalibrate --noReports
  nf_test . --step recalibrate --tools FreeBayes,HaplotypeCaller,MuTect1,MuTect2,Strelka
  # Test whether restarting from an already recalibrated BAM works
  nf_test . --step variantCalling --tools Strelka --noReports
fi

if [[ $TEST = ANNOTATEVEP ]] || [[ $TEST = ANNOTATESNPEFF ]] || [[ $TEST = ALL ]]
then
  nf_test . --step mapping --sample data/tsv/tiny-single-manta.tsv --tools Manta,Strelka
  nf_test . --step mapping --sample data/tsv/tiny-manta.tsv --tools Manta,Strelka
  nf_test . --step mapping --sample $SAMPLE --tools MuTect2

  # Remove images only on TRAVIS
  if [[ $PROFILE == docker ]] && [[ $TRAVIS == true ]]
  then
    docker rmi -f maxulysse/caw:${TAG} maxulysse/fastqc:${TAG} maxulysse/gatk:${TAG} maxulysse/picard:${TAG}
  elif [[ $PROFILE == singularity ]] && [[ $TRAVIS == true ]]
  then
    rm -rf work/singularity/caw-${TAG}.img work/singularity/fastqc-${TAG}.img work/singularity/gatk-${TAG}.img work/singularity/picard-${TAG}.img
  fi
  if [[ $TEST != ANNOTATESNPEFF ]]
  then
    nf_test . --step annotate --tools VEP --annotateTools Manta,Strelka
    nf_test . --step annotate --tools VEP --annotateVCF VariantCalling/Manta/Manta_9876T_vs_1234N.diploidSV.vcf.gz,VariantCalling/Manta/Manta_9876T_vs_1234N.somaticSV.vcf.gz --noReports
    nf_test . --step annotate --tools VEP --annotateVCF VariantCalling/Manta/Manta_9876T_vs_1234N.diploidSV.vcf.gz --noReports
  fi
  if [[ $TEST != ANNOTATEVEP ]]
  then
    nf_test . --step annotate --tools snpEff --annotateTools Manta,Strelka
    nf_test . --step annotate --tools snpEff --annotateVCF VariantCalling/Manta/Manta_9876T_vs_1234N.diploidSV.vcf.gz,VariantCalling/Manta/Manta_9876T_vs_1234N.somaticSV.vcf.gz --noReports
    nf_test . --step annotate --tools snpEff --annotateVCF VariantCalling/Manta/Manta_9876T_vs_1234N.diploidSV.vcf.gz --noReports
  fi
fi

if [[ $TEST = BUILDCONTAINERS ]] || [[ $TEST = ALL ]]
then
  nf_test buildContainers.nf --docker --containers caw,fastqc,gatk,igvtools,multiqc,mutect1,picard,qualimap,runallelecount,r-base,snpeff
fi
