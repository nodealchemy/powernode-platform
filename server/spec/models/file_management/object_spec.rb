# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FileManagement::Object, type: :model do
  let(:account) { create(:account) }
  let(:storage) { create(:file_storage, account: account) }
  let(:file_object) { create(:file_object, account: account, storage: storage) }

  # IMP-d97f6e3bbc2b (landing pass): the provider is built INSIDE the
  # after_destroy's rescue. An ordinary, non-strict destroy whose provider
  # factory raises logs and proceeds, exactly as before the erasure work;
  # only the erasure's strict mode turns a failed blob removal into a raise
  # that rolls the row back.
  describe '#remove_from_storage' do
    context 'when the storage provider cannot even be constructed' do
      before do
        allow(StorageProviderFactory).to receive(:create).and_raise(RuntimeError, 'no such provider')
      end

      it 'still destroys the row on a non-strict destroy' do
        id = file_object.id

        expect(file_object.destroy).to be_truthy
        expect(described_class.exists?(id)).to be false
      end

      it 'rolls the row back on a strict destroy and never reports a false success' do
        id = file_object.id
        file_object.strict_storage_removal = true

        expect { file_object.destroy! }
          .to raise_error(FileManagement::Object::StorageRemovalFailed) { |e| expect(e.reason).to be_nil }
        expect(described_class.exists?(id)).to be true
      end
    end

    it 'carries the provider refusal reason on a strict destroy' do
      provider = instance_double(StorageProviders::LocalStorage, delete_file: false, initialize_storage: true,
                                                                last_removal_refusal: 'store_not_initialized')
      # Created first: the storage memoizes the provider its creation built.
      file_object.reload
      allow(StorageProviderFactory).to receive(:create).and_return(provider)
      file_object.strict_storage_removal = true

      expect { file_object.destroy! }
        .to raise_error(FileManagement::Object::StorageRemovalFailed, /store_not_initialized/) { |e|
          expect(e.reason).to eq('store_not_initialized')
        }
    end
  end
end
