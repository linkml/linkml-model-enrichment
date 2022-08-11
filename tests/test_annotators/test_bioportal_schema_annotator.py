# -*- coding: utf-8 -*-
import logging
import unittest
from linkml.utils.schema_builder import SchemaBuilder
from linkml_runtime.dumpers import yaml_dumper
from linkml_runtime.linkml_model import SchemaDefinition, EnumDefinition, PermissibleValue
from oaklib.implementations import BioportalImplementation

from schema_automator.annotators.schema_annotator import SchemaAnnotator

from schema_automator.generalizers.generalizer import DEFAULT_SCHEMA_NAME


class BioPortalSchemaAnnotatorTestCase(unittest.TestCase):
    """
    Tests schema annotator using bioportal.

    Note that currently this test will be skipped on github actions.

    To run this test locally follow the OAK instructions for setting the Bioportal API key
    """

    def setUp(self) -> None:
        impl = BioportalImplementation()
        try:
            impl.load_bioportal_api_key()
        except ValueError:
            self.skipTest("Skipping bioportal tests, no API key set")
        self.annotator = SchemaAnnotator(impl, curie_only=True, mine_descriptions=True)

    def test_ann(self):
        sb = SchemaBuilder(DEFAULT_SCHEMA_NAME)
        s = sb.schema
        sb.add_class('Gene').add_slot('symbol')
        sb.add_enum('GeneType')
        e = s.enums['GeneType']
        # Test case involves use of CamelCase
        pv1 = PermissibleValue('ProteinCodingGene', description='protein coding gene')
        pv2 = PermissibleValue('RNAGene', description='RNA gene')
        e.permissible_values[pv1.text] = pv1
        e.permissible_values[pv2.text] = pv2
        self.annotator.annotate_schema(s)
        logging.info(yaml_dumper.dumps(s))
        gene = list(s.classes.values())[0]
        self.assertIn('SO:0000704', gene.exact_mappings)
        gene_type = list(s.enums.values())[0]
        #self.assertIn('NCIT:C25284', gene_type.exact_mappings)
        #for pv in gene_type.permissible_values.values():
        #    self.assertIsNotNone(pv.meaning)
        #    self.assertGreater(len(pv.exact_mappings), 1)


