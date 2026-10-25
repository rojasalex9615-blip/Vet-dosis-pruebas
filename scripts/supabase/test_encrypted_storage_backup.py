import io
import json
from pathlib import Path
import tempfile
import unittest

from encrypted_storage_backup import (
    configuration_status, create_backup, object_inventory,
)


class StorageBackupTest(unittest.TestCase):
    def test_configuration_requires_all_three_secrets(self):
        self.assertFalse(configuration_status({})['configuration_valid'])
        self.assertTrue(configuration_status({
            'SUPABASE_ACCESS_TOKEN': 'synthetic-management-token',
            'SUPABASE_TEST_STORAGE_SERVICE_ROLE_KEY': 'synthetic-service-role-key-123',
            'SUPABASE_TEST_BACKUP_PASSPHRASE': 'synthetic-test-passphrase-123',
        })['configuration_valid'])

    def test_inventory_rejects_duplicates_and_unexpected_fields(self):
        rows = [{'bucket_id': 'private', 'name': 'one.png'}]
        self.assertEqual(object_inventory(lambda _: rows), rows)
        with self.assertRaises(ValueError):
            object_inventory(lambda _: rows + rows)
        with self.assertRaises(ValueError):
            object_inventory(lambda _: [{'bucket_id': 'private', 'name': 'one.png', 'owner': 'secret'}])

    def test_real_encryption_and_recovery_check_cover_every_binary(self):
        rows = [{'bucket_id': 'private', 'name': 'folder/patient-note.png'},
                {'bucket_id': 'other', 'name': 'blank.bin'}]
        bodies = [b'synthetic image bytes', b'']
        calls = []

        def opener(request, timeout):
            calls.append(request.full_url)
            return io.BytesIO(bodies[len(calls)-1])

        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / 'encrypted'
            result = create_backup(output, 'synthetic-service-role-key-123',
                                   'synthetic-test-passphrase-123', rows, opener)
            self.assertEqual(result['objects'], 2)
            self.assertEqual(result['plaintext_object_bytes'], len(bodies[0]))
            self.assertTrue(result['binary_integrity_verified'])
            self.assertEqual(len(list(output.glob('*.tar.gpg'))), 1)
            self.assertNotIn('patient-note', (output / 'manifest.json').read_text())
            self.assertNotIn('synthetic image', (output / 'manifest.json').read_text())
            self.assertEqual(json.loads((output / 'manifest.json').read_text())['objects'], 2)
        self.assertEqual(len(calls), 2)


if __name__ == '__main__':
    unittest.main()
