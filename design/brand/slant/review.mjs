// Slant refinement review. Ratings: g = passes, o = marginal, w = fails.
export const criteria = [
  ['m','Does the M read?'],['t','Does the T read?'],['px16','Both still read at 16 px'],['pop','Has energy (in one colour)'],
  ['calm','Sits calmly among Mac app icons'],['square','Fills the square icon evenly'],['counter','V stays open at small sizes'],
  ['bmw','Distance from BMW M and sports marks'],
];
export const review = {
  s12: { verdict: 'Recommended', r: {m:'g',t:'g',px16:'g',pop:'g',calm:'o',square:'o',counter:'g',bmw:'o'},
    note: 'Keeps the energy you picked, at a lean the eye reads as confident writing rather than racing. Diagonals of 15 instead of 17 open the V so the M no longer clots at 16 px. The wedge cut on the crossbar is the mark’s one flourish, so it stays.' },
  s8: { verdict: 'Fallback', r: {m:'g',t:'g',px16:'g',pop:'o',calm:'g',square:'g',counter:'g',bmw:'g'},
    note: 'The calmest and most Mac-like, and the furthest from BMW M. It fills the square best. It gives up part of the energy that made Slant win, and at 16 px it starts to look like an upright MT again.' },
  s15: { verdict: 'Too fast', r: {m:'g',t:'g',px16:'o',pop:'g',calm:'w',square:'w',counter:'o',bmw:'w'},
    note: 'The loudest. The skew shears the M’s bottom-left corner out of the icon’s balance and leaves an empty top-left. It reads as sport or motoring, and is the closest to BMW M.' },
  p12: { verdict: 'Rejected detail', r: {m:'g',t:'g',px16:'g',pop:'o',calm:'g',square:'o',counter:'g',bmw:'o'},
    note: 'Cutting the crossbar parallel to the lean is tidier but inert. The crossbar then just stops, and the mark loses the flick that gives it “pop”. Keep the wedge.' },
};
export const order = ['s12','s8','s15','p12'];
