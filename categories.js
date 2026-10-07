/* Pouch – starter grocery categories and the words that put items in them.
   Each category has a name in English, German and Norwegian, and a word list
   that mixes all three languages. Items can match several categories.
   Order = a typical walk through a supermarket. */
const STARTER_CATEGORIES = [
  { key:'produce', en:'Fruit & veg', de:'Obst & Gemüse', no:'Frukt og grønt', words:`
    apple apples banana bananas orange oranges lemon lemons lime limes grape grapes pear pears peach peaches plum plums
    cherry cherries strawberry strawberries raspberry raspberries blueberry blueberries berries melon watermelon pineapple
    mango kiwi avocado avocados tomato tomatoes cucumber lettuce salad spinach kale cabbage broccoli cauliflower carrot carrots
    potato potatoes onion onions garlic ginger pepper peppers chili chilli zucchini courgette eggplant aubergine mushroom mushrooms
    leek celery corn peas asparagus radish radishes beetroot pumpkin squash herbs parsley basil coriander cilantro dill mint
    rocket arugula fennel shallot shallots springonion springonions sweetpotato
    apfel äpfel banane bananen orange orangen zitrone zitronen limette limetten trauben weintrauben birne birnen pfirsich
    pflaume pflaumen kirsche kirschen erdbeere erdbeeren himbeere himbeeren heidelbeeren blaubeeren beeren melone wassermelone
    ananas tomate tomaten gurke gurken salat kopfsalat spinat grünkohl kohl rotkohl weißkohl brokkoli blumenkohl karotte karotten
    möhre möhren kartoffel kartoffeln zwiebel zwiebeln knoblauch ingwer paprika peperoni pilze champignons lauch porree sellerie
    erbsen spargel radieschen rotebete kürbis kräuter petersilie basilikum koriander minze rucola fenchel schalotte schalotten
    frühlingszwiebeln süßkartoffel
    eple epler banan bananer appelsin appelsiner sitron sitroner druer pære pærer fersken plomme plommer kirsebær jordbær
    bringebær blåbær bær vannmelon avokado tomat tomater agurk spinat grønnkål kål rødkål hodekål brokkoli blomkål gulrot
    gulrøtter potet poteter løk rødløk hvitløk ingefær sopp sjampinjong champinjong purre selleri erter asparges reddik rødbete
    gresskar urter persille mynte ruccola fennikel sjalottløk vårløk søtpotet` },
  { key:'bakery', en:'Bread & bakery', de:'Brot & Backwaren', no:'Brød og bakervarer', words:`
    bread loaf rolls roll baguette bagel bagels croissant croissants buns bun toast tortilla tortillas wraps pita muffin muffins
    cake donut donuts sourdough
    brot brötchen semmel semmeln toastbrot brezel brezeln kuchen vollkornbrot fladenbrot knäckebrot
    brød rundstykker rundstykke loff baguett boller bolle polarbrød lomper lompe knekkebrød kake wienerbrød kneippbrød grovbrød
    pitabrød` },
  { key:'deli', en:'Cold cuts & spreads', de:'Aufschnitt & Aufstriche', no:'Pålegg', words:`
    ham salami prosciutto pepperoni jam marmalade peanutbutter nutella hummus pate pâté spread coldcuts
    schinken aufschnitt marmelade konfitüre leberwurst frischkäse erdnussbutter brotaufstrich
    skinke spekeskinke pålegg syltetøy nugatti leverpostei makrellitomat kaviar prim brunost servelat fårepølse peanøttsmør
    smøreost` },
  { key:'meat', en:'Meat', de:'Fleisch', no:'Kjøtt', words:`
    chicken beef pork mince minced steak steaks sausage sausages bacon lamb turkey meatballs burger burgers chops ribs
    drumsticks wings meat
    hähnchen hühnchen huhn rind rindfleisch schwein schweinefleisch hackfleisch hack wurst würstchen bratwurst speck lamm
    pute putenbrust frikadellen hamburger fleisch schnitzel
    kylling kyllingfilet kjøttdeig karbonadedeig storfe biff svin svinekjøtt pølse pølser lammekjøtt kalkun kjøttkaker
    kjøttboller kjøtt ribbe koteletter pinnekjøtt kebab` },
  { key:'fish', en:'Fish & seafood', de:'Fisch & Meeresfrüchte', no:'Fisk og sjømat', words:`
    fish salmon tuna cod shrimp shrimps prawns mussels crab trout mackerel herring sardines fishcakes fishsticks seafood
    fisch lachs thunfisch kabeljau dorsch garnelen krabben muscheln forelle makrele hering sardinen fischstäbchen
    fisk laks tunfisk torsk sei hyse reker scampi blåskjell krabbe ørret makrell sild sardiner fiskekaker fiskeboller
    fiskepinner fiskegrateng lutefisk klippfisk` },
  { key:'dairy', en:'Dairy & eggs', de:'Milchprodukte & Eier', no:'Meieri og egg', words:`
    milk butter cheese cream yoghurt yogurt eggs egg sourcream cottagecheese mozzarella parmesan cheddar feta margarine kefir
    quark buttermilk skyr cremefraiche
    milch butter käse sahne schlagsahne joghurt eier ei schmand quark frischkäse buttermilch
    melk lettmelk helmelk skummetmelk smør ost hvitost brunost gulost smøreost fløte kremfløte matfløte rømme lettrømme
    yoghurt egg margarin kulturmelk kesam cottage norvegia jarlsberg gouda brie camembert ricotta mascarpone halloumi` },
  { key:'dry', en:'Pasta, rice & grains', de:'Nudeln, Reis & Getreide', no:'Pasta, ris og korn', words:`
    pasta spaghetti penne fusilli macaroni lasagne noodles rice couscous quinoa bulgur lentils
    nudeln reis linsen
    spagetti makaroni nudler ris linser` },
  { key:'baking', en:'Baking', de:'Backen', no:'Baking', words:`
    flour sugar yeast bakingpowder bakingsoda vanilla cocoa icingsugar chocolatechips butter nuts honey
    mehl zucker hefe backpulver vanillezucker kakao puderzucker natron
    mel hvetemel sammalt sukker gjær bakepulver natron vaniljesukker melis` },
  { key:'canned', en:'Canned & jars', de:'Konserven', no:'Hermetikk', words:`
    beans chickpeas soup passata coconutmilk cannedtomatoes olives pickles tuna corn
    bohnen kichererbsen suppe kokosmilch dosentomaten oliven gurken
    bønner kikerter suppe kokosmelk hermetikk hakkedetomater oliven sylteagurk` },
  { key:'spices', en:'Spices & sauces', de:'Gewürze & Soßen', no:'Krydder og sauser', words:`
    salt pepper spices oregano cinnamon curry ketchup mustard mayonnaise mayo sauce soysauce vinegar oil oliveoil pesto
    stock bouillon dressing salsa
    salz pfeffer gewürze zimt ketchup senf soße sauce sojasoße essig öl olivenöl brühe
    krydder kanel karri sennep majones saus soyasaus eddik olje olivenolje buljong tacokrydder` },
  { key:'breakfast', en:'Breakfast & cereal', de:'Frühstück & Müsli', no:'Frokost', words:`
    cereal muesli granola oats oatmeal porridge honey cornflakes juice yoghurt
    müsli haferflocken honig
    frokostblanding havregryn honning` },
  { key:'snacks', en:'Snacks & sweets', de:'Snacks & Süßes', no:'Snacks og godteri', words:`
    chips crisps chocolate candy sweets cookies biscuits crackers nuts popcorn snacks
    schokolade süßigkeiten kekse nüsse gummibärchen
    potetgull sjokolade godteri smågodt kjeks nøtter` },
  { key:'drinks', en:'Drinks', de:'Getränke', no:'Drikke', words:`
    water juice soda coke cola beer wine coffee tea lemonade
    wasser saft limo bier wein kaffee tee sprudel
    vann brus øl vin kaffe te farris mineralvann` },
  { key:'frozen', en:'Frozen', de:'Tiefkühl', no:'Frysevarer', words:`
    frozen icecream pizza fries
    tiefkühl eis tiefkühlpizza pommes
    frossen frosne is iskrem pinneis softis` },
  { key:'household', en:'Household & cleaning', de:'Haushalt & Putzen', no:'Husholdning', words:`
    toiletpaper papertowels kitchenroll detergent dishsoap bin binbags trashbags foil clingfilm batteries candles sponges
    cleaner bleach
    toilettenpapier küchenrolle spülmittel waschmittel müllbeutel alufolie frischhaltefolie batterien kerzen schwämme reiniger
    dopapir toalettpapir tørkerull oppvaskmiddel vaskemiddel zalo søppelposer aluminiumsfolie plastfolie batterier
    stearinlys svamp klut kluter` },
  { key:'personal', en:'Personal care', de:'Drogerie', no:'Personlig pleie', words:`
    shampoo conditioner soap toothpaste toothbrush deodorant razor lotion sunscreen tissues plasters painkillers
    spülung seife zahnpasta zahnbürste deo rasierer sonnencreme taschentücher pflaster
    sjampo balsam såpe tannkrem tannbørste barberhøvel solkrem lommetørkle plaster bind tamponger` },
];

const STARTER_LANGS = { no:'Norsk', de:'Deutsch', en:'English' };

/* word -> [category keys] */
const STARTER_WORDS = (() => {
  const m = new Map();
  for (const c of STARTER_CATEGORIES)
    for (const w of c.words.split(/\s+/).filter(Boolean)) {
      const k = w.toLowerCase();
      if (!m.has(k)) m.set(k, new Set());
      m.get(k).add(c.key);
    }
  return m;
})();
const STARTER_LONG = [...STARTER_WORDS.keys()].filter(w => w.length >= 4).sort((a, b) => b.length - a.length);

function starterNormalize(text){
  return text.toLowerCase()
    .replace(/[éèê]/g, 'e').replace(/[îï]/g, 'i').replace(/ô/g, 'o').replace(/â/g, 'a')
    .replace(/[^a-z0-9æøåäöüß]+/g, ' ').trim();
}
function starterLookup(token){
  // exact, then with common plural/definite endings removed (en, de, no)
  if (STARTER_WORDS.has(token)) return STARTER_WORDS.get(token);
  for (const end of ['ene', 'ane', 'es', 'en', 'er', 'et', 'n', 'r', 's', 'e']) {
    if (token.length - end.length >= 3 && token.endsWith(end)) {
      const t = token.slice(0, -end.length);
      if (STARTER_WORDS.has(t)) return STARTER_WORDS.get(t);
    }
  }
  return null;
}
function starterCompound(token){
  // Compound words: the last part usually decides (Vollmilch, appelsinjuice), else the first (kyllingfilet)
  for (const w of STARTER_LONG) if (token.length > w.length && token.endsWith(w)) return STARTER_WORDS.get(w);
  for (const w of STARTER_LONG) if (token.length > w.length && token.startsWith(w)) return STARTER_WORDS.get(w);
  return null;
}
/* Guess starter category keys for an item's text. */
function guessCategoryKeys(text){
  const norm = starterNormalize(text);
  if (!norm) return [];
  const tokens = norm.split(' ').filter(t => !/^\d+$/.test(t));
  const joined = tokens.join('');
  let hit = STARTER_WORDS.get(joined) || (tokens.length > 1 && starterLookup(joined));
  // the last word is usually the main one ("orange juice", "chicken breast" -> chicken)
  for (let i = tokens.length - 1; !hit && i >= 0; i--) hit = starterLookup(tokens[i]);
  for (let i = tokens.length - 1; !hit && i >= 0; i--) hit = starterCompound(tokens[i]);
  return hit ? [...hit] : [];
}
