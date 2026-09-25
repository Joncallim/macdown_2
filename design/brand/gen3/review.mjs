// Gen-3 review. Ratings: g = passes, o = marginal, w = fails.
export const criteria = [
  ['m','Does the M read?'],['t','Does the T read?'],['px16','Both still read at 16 px'],
  ['pop','Has energy (in one colour)'],['distinct','Silhouette distinctiveness'],['balance','Optical balance'],
  ['mud','Stays clean (no mud)'],['mono','Monochrome'],['ld','Light / dark'],
  ['mac','Fits a native macOS writing app'],['generic','Avoids generic or look-alike marks'],
];
export const review = {
  caret: { verdict: 'Finalist', r: {m:'g',t:'g',px16:'g',pop:'g',distinct:'g',balance:'o',mud:'g',mono:'g',ld:'g',mac:'g',generic:'g'},
    note: 'The T is also the text cursor you type with, so the mark says “editor” without a tagline. The foot serif is the one gesture no other MT monogram has, and it survives at 16 px. In two colours the cursor is the part that lights up. The risk is that the foot pulls the T towards an I, giving “MI”. The weight also sits on the right, so the mark needs optical centring.' },
  slant: { verdict: 'Finalist', r: {m:'g',t:'g',px16:'g',pop:'g',distinct:'o',balance:'g',mud:'g',mono:'g',ld:'g',mac:'o',generic:'o'},
    note: 'The most energetic: heavy strokes, a forward lean like handwriting, and an angled cut at the end of the crossbar. It is very solid at 16 px. The energy comes from speed, which is less calm than most macOS icons. Italic M monograms are close to sports and car branding (BMW’s M division is the obvious neighbour).' },
  soft: { verdict: 'Reserve', r: {m:'g',t:'g',px16:'o',pop:'o',distinct:'o',balance:'g',mud:'o',mono:'g',ld:'g',mac:'g',generic:'o'},
    note: 'Friendly and approachable, and the closest to 01 Fluid in personality. It is warm rather than punchy. The round ends blur together at 16 px, and rounded monoline letters are a common look for apps and SaaS products.' },
  contrast: { verdict: 'Dropped', r: {m:'g',t:'g',px16:'w',pop:'o',distinct:'o',balance:'o',mud:'o',mono:'g',ld:'g',mac:'g',generic:'g'},
    note: 'Elegant and literary, like a book-face capital. The hairline diagonals turn grey at 32 px and are gone at 16. That is exactly where an app icon has to work, so it fails.' },
};
export const order = ['caret','slant','soft','contrast'];
