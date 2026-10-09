// Design review content for the board. Ratings: g = passes, o = marginal, w = fails.
export const criteria = [
  ['m','Does the M read?'],['t','Does the T read?'],['px16','Both still read at 16 px'],
  ['distinct','Silhouette distinctiveness'],['balance','Optical balance'],['neg','Negative space'],
  ['mud','Stays clean (no mud)'],['dom','Neither letter overwhelms'],['mono','Monochrome'],
  ['ld','Light / dark'],['mac','Fits a native macOS writing app'],['generic','Avoids generic SaaS / dev-tool look'],
];
export const review = {
  crown: { verdict: 'Finalist', r: {m:'g',t:'g',px16:'g',distinct:'g',balance:'o',neg:'g',mud:'g',dom:'g',mono:'g',ld:'g',mac:'g',generic:'o'},
    note: 'The V notch gives a capital M its peaks, and the long stem gives the T. Both read without any explanation. The notch is still 2 px deep at 16 px. The shape is top-heavy, and there is some kinship with Tesla’s T and with a T-shirt silhouette.' },
  ligature: { verdict: 'Finalist', r: {m:'g',t:'g',px16:'o',distinct:'o',balance:'o',neg:'o',mud:'o',dom:'o',mono:'g',ld:'g',mac:'g',generic:'o'},
    note: 'The most literal of the four: it reads “MT” instantly. At 16 px the M’s V fills in and the crossbar merges with the M’s right peak. It is asymmetric and slightly M-led. It looks more like initials than a symbol, and MT monograms are common.' },
  arch: { verdict: 'Reserve: fold into Crown', r: {m:'o',t:'g',px16:'g',distinct:'o',balance:'g',neg:'g',mud:'g',dom:'o',mono:'g',ld:'g',mac:'g',generic:'g'},
    note: 'The friendliest and closest to 01 Fluid. It is very robust at 16 px. The m has to be looked for: at first glance it reads as a T on legs, or as π or a small table. Its soft shoulders are the right personality to lend to Crown.' },
  gate: { verdict: 'Dropped', r: {m:'g',t:'w',px16:'o',distinct:'w',balance:'g',neg:'o',mud:'g',dom:'w',mono:'g',ld:'g',mac:'o',generic:'w'},
    note: 'A clear, square M. The T only appears once it is pointed out, because the short stem reads as the M’s middle V. Visually it sits with transport signage and other square-M marks. It fails the brief.' },
};
export const order = ['crown','ligature','arch','gate'];
