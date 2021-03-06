describe Course do
  let(:c1) { create(:course) }

  describe '.name' do
    it 'must present' do
      c1.name = ''
      expect(c1).to be_invalid
    end
  end

  describe '.section' do
    it 'must present' do
      c1.section = ''
      expect(c1).to be_invalid
    end
  end

  describe 'uniqueness' do
    it 'is invalid with same name, section, and term' do
      c2 = described_class.new(name: c1.name, section: c1.section, term: c1.term)
      c2.save
      expect(c2).to be_invalid
    end
  end
end
