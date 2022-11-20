RUN = poetry run
VERSION = $(shell git tag | tail -1)

.PHONY: all clean test

all: clean test target/soil_meanings.yaml


clean:
	rm -rf target/soil_meanings.yaml
	rm -rf target/soil_meanings_generated.yaml
	rm -rf target/availabilities_g_s_strain_202112151116.yaml
	rm -rf target/availabilities_g_s_strain_202112151116_org_meanings.yaml

test:
	$(RUN) pytest tests/

schema_automator/metamodels/%.py: schema_automator/metamodels/%.yaml
	$(RUN) gen-python $< > $@.tmp && mv $@.tmp $@

# tried to find a single meaning for each permissible value
# unlike term mapping, which can tolerate multiple mapped terms
target/soil_meanings.yaml: tests/resources/mixs/terms.yaml
	poetry run enum_annotator \
		--modelfile $< \
		--requested_enum_name fao_class_enum \
		--ontology_string ENVO > $@

# validate that it's still valid LinkML
# FileNotFoundError: [Errno 2] No such file or directory: '/Users/MAM/Documents/gitrepos/linkml-model-enrichment/target/ranges.yaml'
# cp tests/resources/mixs/*yaml target
target/soil_meanings_generated.yaml: target/soil_meanings.yaml
	poetry run gen-yaml $< > $@

# requires Felix files
# add demonstration SQL file
target/availabilities_g_s_strain_202112151116.yaml: local/availabilities_g_s_strain_202112151116.tsv
	poetry run tsv2linkml \
		--enum-columns organism \
		--output $@ \
		--class_name availabilities \
		--schema_name availabilities $<

#OMOP_TABLE_NAMES=CONCEPT_RELATIONSHIP_HEAD CONCEPT_ANCESTOR CONCEPT_CLASS CONCEPT_SYNONYM CONCEPT DOMAIN DRUG_STRENGTH RELATIONSHIP VOCABULARY
OMOP_TABLE_NAMES=CONCEPT_RELATIONSHIP_HEAD CONCEPT_ANCESTOR CONCEPT_CLASS CONCEPT_SYNONYM CONCEPT DOMAIN RELATIONSHIP VOCABULARY
OMOP_TABLES=$(foreach r,$(OMOP_TABLE_NAMES), local/$(r).csv)

target/omop_5.yaml: $(OMOP_TABLES)
	$(RUN) schemauto generalize-tsvs --add-container-class true --schema-name omop_vocabulary $^ > $@

#target/omop_relationship.yaml: local/CONCEPT_RELATIONSHIP.csv
#	schemauto generalize-tsv --class-name omop_relationship --schema-name omop_relationship $^ > $@

target/%.yaml: local/%.csv
	schemauto generalize-tsv --class-name $* --schema-name $* $^ > $@


target/omop_person.yaml: local/person.tsv
	schemauto generalize-tsv --class-name Person --schema-name omop_person $^ > $@

build-omop:
	$(MAKE) target/omop_person.yaml -B
	$(MAKE) target/omop_5.yaml -B

target/cpath_patient_manual.yaml:
	echo "This file had to be manually hacked to be translateable"

target/cpath_patient.ttl: target/cpath_patient_manual.yaml
	linkml-convert -t rdf -s $< -m target/cpath_patient_manual.py -S person_list -C Person local/person.tsv

target/model target/model/%:
	mkdir -p $@

target/omop_%.ttl: #target/omop_5.yaml
	linkml-convert -t rdf -s target/omop_5.yaml -S domains -C DOMAINTABLE local/$*.csv

target/omop_5.py: target/omop_5.yaml | target/model/omop_5
	$(RUN) gen-project -d target/model/omop_5 $< && mv target/model/omop_5/*.py target/

omop:
	$(MAKE) target/omop_DOMAIN.ttl

target/cpath_patient_manual.py: target/cpath_patient_manual.yaml | target/model
	$(RUN) gen-project -d target/model $< && mv target/model/*.py target/

target/omop_relationship.ttl: target/omop_concepts.yaml
	linkml-convert -t rdf -s $< -S concept_id_1 -C CONCEPT_RELATIONSHIP local/CONCEPT_RELATIONSHIP_HEAD.csv

# KeyError: 'iri' could mean that an unrecognized ontology name was used
target/availabilities_g_s_strain_202112151116_org_meanings.yaml: target/availabilities_g_s_strain_202112151116.yaml
	poetry run enum_annotator \
		--modelfile $< \
		--requested_enum_name organism_enum \
		--ontology_string NCBITAXON > $@

target/availabilities_g_s_strain_202112151116_org_meanings_curateable.tsv: target/availabilities_g_s_strain_202112151116_org_meanings.yaml
	poetry run enums_to_curateable \
		--modelfile $< \
		--enum organism_enum \
		--tsv_out $@


# do some curation on target/availabilities_g_s_strain_202112151116_org_meanings_curateable.tsv
#   and save as target/availabilities_g_s_strain_202112151116_org_meanings_curated.txt
# Excel wants to call it "*.txt". I'm saving as UTF 16 so I can be sure about the encoding at import time.

target/availabilities_g_s_strain_202112151116_org_meanings_curated.yaml: target/availabilities_g_s_strain_202112151116_org_meanings_curated.txt
	poetry run curated_to_enums \
		--tsv_in $< \
		--tsv_encoding utf_16 \
		--model_in target/availabilities_g_s_strain_202112151116_org_meanings.yaml \
		--curated_yaml $@ \
		--selected_enum organism_enum

# create a convenient wrapper script;
# this can be used outside the poetry environment
bin/schemauto:
	echo `poetry run which schemauto` '"$$@"' > $@ && chmod +x $@


################################################
#### Commands for building the Docker image ####
################################################

IM=linkml/schema-automator

docker-build-no-cache:
	@docker build --no-cache -t $(IM):$(VERSION) . \
	&& docker tag $(IM):$(VERSION) $(IM):latest

docker-build:
	@docker build -t $(IM):$(VERSION) . \
	&& docker tag $(IM):$(VERSION) $(IM):latest

docker-build-use-cache-dev:
	@docker build -t $(DEV):$(VERSION) . \
	&& docker tag $(DEV):$(VERSION) $(DEV):latest

docker-clean:
	docker kill $(IM) || echo not running ;
	docker rm $(IM) || echo not made 

docker-publish-no-build:
	@docker push $(IM):$(VERSION) \
	&& docker push $(IM):latest

docker-publish-dev-no-build:
	@docker push $(DEV):$(VERSION) \
	&& docker push $(DEV):latest

docker-publish: docker-build
	@docker push $(IM):$(VERSION) \
	&& docker push $(IM):latest

docker-run:
	@docker run  -v $(PWD):/work -w /work -ti $(IM):$(VERSION) 
